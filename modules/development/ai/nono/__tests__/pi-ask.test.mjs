import assert from "node:assert/strict";
import * as Effect from "effect/Effect";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, statSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createConnection, createServer } from "node:net";
import { defaultCapabilities } from "../scripts/ipc/policy.mts";
import { neovimProvider } from "../scripts/ipc/providers/neovim/provider.mts";
import { startJsonLinesServer } from "../scripts/ipc/json-lines-server.mts";

const launchId = "0123456789abcdef0123456789abcdef";
const capability = defaultCapabilities.capabilities["neovim-ask"];

function frames(stream) {
  const lines = createInterface({ input: stream });
  const iterator = lines[Symbol.asyncIterator]();
  return {
    async next() {
      let timer;
      try {
        const line = await Promise.race([iterator.next(), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error("Frame timeout")), 5000); })]);
        if (line.done) throw new Error("Peer closed");
        return JSON.parse(line.value);
      } finally { clearTimeout(timer); }
    },
    close: () => lines.close(),
  };
}
async function connect(path) {
  const socket = createConnection(path);
  const input = frames(socket);
  await once(socket, "connect");
  return {
    socket, ...input,
    send: message => socket.write(JSON.stringify(message) + "\n"),
    async stop() { if (!socket.destroyed) { const closed = once(socket, "close"); socket.end(); await closed; } input.close(); },
  };
}

test("Neovim provider binds, pushes prompts, acknowledges and replaces sessions through the shared broker", {
  skip: !process.env.NVIM_TEST_BINARY, timeout: 30000,
}, async () => {
  const root = realpathSync(mkdtempSync("/tmp/piask-"));
  const home = join(root, "home");
  mkdirSync(home, { mode: 0o700 });
  const child = spawn(process.env.NVIM_TEST_BINARY, ["--headless", "-u", "NONE", "-i", "NONE", "-l", fileURLToPath(new URL("./fixtures/neovim-host.lua", import.meta.url))], {
    cwd: root, env: { HOME: home, PI_ASK_TEST_CWD: root },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const exited = once(child, "exit");
  const events = frames(child.stdout);
  let errors = "";
  child.stderr.on("data", chunk => { errors += chunk; });
  let server, service;
  try {
    const ready = await events.next();
    const endpoint = join(root, "broker.sock");
    const context = { launchId, cwd: root, home, uid: process.getuid() };
    service = neovimProvider.serve({ upstream: ready.socketPath, context }, capability, root);
    server = await startJsonLinesServer({ capability, endpoint, ...service });
    assert.equal(statSync(endpoint).mode & 0o777, 0o600);
    // These requests must fail before creating an editor binding, not merely fail in Neovim.
    for (const message of [
      { id: "bad", method: "nvim_exec_lua", params: { code: "return os.execute('false')" } },
      { id: "bad", method: "neovim.bind", params: { launchId, cwd: root + "-other", sessionId: "one" } },
      { id: "bad", method: "neovim.bind", params: { launchId: "f".repeat(32), cwd: root, sessionId: "one" } },
      { id: "bad", method: "neovim.bind", params: { launchId, cwd: root, sessionId: "one", channelId: 1 } },
      { id: "bad", method: "neovim.ack", params: { payload: {} } },
    ]) {
      const client = await connect(endpoint);
      client.send(message);
      assert.equal((await client.next()).error.code, "PI_IPC_DENIED");
      await client.stop();
    }
    for (const sessionId of ["first-session", "replacement-session"]) {
      const client = await connect(endpoint);
      client.send({ id: "bind", method: "neovim.bind", params: { launchId, cwd: root, sessionId } });
      const bound = await client.next();
      assert.equal(bound.ok, true);
      assert.equal(bound.result.sessionId, sessionId);
      assert.equal(bound.result.cwd, root);
      const event = await events.next();
      assert.equal(event.event, "bind");
      const prompt = await client.next();
      assert.equal(prompt.method, "neovim.prompt");
      assert.equal(prompt.params.text, "explain æøå");
      client.send({ id: "ack", method: "neovim.ack", params: { payload: {
        version: 1, requestId: prompt.params.requestId, launchId, sessionId, ownerId: "test-owner", outcome: "accepted", state: "idle",
      } } });
      assert.equal((await client.next()).ok, true);
      assert.equal((await events.next()).event, "ack");
      if (sessionId === "first-session") {
        client.send({ id: "forged", method: "neovim.ack", params: { payload: {
          version: 1, requestId: prompt.params.requestId, launchId, sessionId, ownerId: "another-owner", outcome: "accepted", state: "idle",
        } } });
        assert.equal((await client.next()).error.code, "PI_IPC_DENIED");
      } else client.send({ id: "close", method: "neovim.close", params: {} });
      const closed = await events.next();
      assert.equal(closed.event, "closed");
      await client.stop();
    }
    assert.deepEqual(await events.next(), { event: "done", bindCount: 2, ackCount: 2, closeCount: 2 });
    assert.equal((await exited)[0], 0, errors);
  } finally {
    await server?.close();
    await service?.dispose?.();
    if (child.exitCode === null && child.signalCode === null) child.kill();
    await exited;
    events.close();
    rmSync(root, { recursive: true, force: true });
  }
});

test("Neovim bootstrap captures host identity and exports only the filtered endpoint", async () => {
  const root = realpathSync(mkdtempSync("/tmp/piask-env-"));
  const upstream = join(root, "nvim");
  const server = createServer(socket => socket.destroy());
  try {
    server.listen(upstream);
    await once(server, "listening");
    const inherited = { PI_NVIM_SOCKET: upstream, PI_NVIM_LAUNCH_ID: launchId };
    const forged = { ...inherited, PI_NVIM_SOCKET: "/project/socket", PI_NVIM_LAUNCH_ID: "f".repeat(32), NVIM: upstream };
    let captured;
    const session = {
      inherited, home: root, cwd: root, agentDir: root, args: [],
      startHelper: (env, cap, launch) => { captured = launch; return Effect.succeed({ ...env, [cap.socketEnvironment]: join(root, "filtered") }); },
    };
    const bound = await Effect.runPromise(neovimProvider.start(forged, session, capability));
    assert.equal(captured.upstream, upstream);
    assert.equal(captured.context.launchId, launchId);
    assert.equal(captured.context.cwd, root);
    assert.equal(bound.PI_NVIM_LAUNCH_ID, launchId);
    assert.equal(bound.PI_NVIM_SOCKET, undefined);
    assert.equal(bound.NVIM, undefined);
    assert.equal(bound.PI_NVIM_ASK_SOCKET, join(root, "filtered"));
    const disabled = await Effect.runPromise(neovimProvider.start(forged, { ...session, inherited: {} }, capability));
    assert.deepEqual(disabled, {});
  } finally {
    await new Promise(resolve => server.close(resolve));
    rmSync(root, { recursive: true, force: true });
  }
});
