import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdtempSync, realpathSync, rmSync, statSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { createMessageValidator, selectCapabilities } from "../scripts/ipc-policy.mjs";
import { echoRegistry } from "./fixtures/ipc-registry.mjs";
import { startJsonLinesServer } from "../scripts/json-lines-server.mjs";

function echoCapability() {
  return selectCapabilities(echoRegistry(), "restricted").echo;
}

function exchange(endpoint, value) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(endpoint);
    const chunks = [];
    socket.setTimeout(3000, () => socket.destroy(new Error("Fixture timed out")));
    socket.once("error", reject);
    socket.once("connect", () => socket.write(Buffer.isBuffer(value) ? value : JSON.stringify(value) + "\n"));
    socket.on("data", chunk => {
      chunks.push(chunk);
      if (!chunk.includes(10)) return;
      socket.destroy();
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); } catch (error) { reject(error); }
    });
  });
}

async function fixture(run, respond = socket => socket.end('{"ok":true,"host_private_data":"not forwarded"}\n')) {
  const root = realpathSync(mkdtempSync("/tmp/pi-jsonl-"));
  const endpoint = join(root, "proxy"); const upstream = join(root, "upstream");
  const received = [];
  const peers = new Set();
  const host = createServer(socket => {
    peers.add(socket); socket.once("close", () => peers.delete(socket));
    socket.on("data", chunk => { received.push(JSON.parse(chunk.toString())); respond(socket); });
  });
  let proxy;
  try {
    host.listen(upstream); await once(host, "listening");
    const capability = echoCapability(); const context = { cwd: "/work/selected" };
    proxy = await startJsonLinesServer({ capability, context, endpoint, upstream, validate: createMessageValidator(capability, context) });
    await run({ endpoint, received, proxy });
  } finally {
    await proxy?.close();
    for (const peer of peers) peer.destroy();
    await new Promise(resolve => host.close(resolve));
    rmSync(root, { recursive: true, force: true });
  }
}
const request = params => ({ id: 1, method: "echo.ping", params: { workspace: "/work/selected", ...params } });

test("a configuration-only service shares framing, bindings, sanitized replies and cleanup", async () => {
  await fixture(async ({ endpoint, received, proxy }) => {
    assert.equal(statSync(endpoint).mode & 0o777, 0o600);
    assert.deepEqual(await exchange(endpoint, request({ message: "æøå" })), { id: 1, ok: true });
    assert.deepEqual(received, [request({ message: "æøå" })]);
    for (const value of [request({ workspace: "/work/other" }), request({ command: "id" }), { ...request(), method: "pane.send_input" }]) {
      assert.equal((await exchange(endpoint, value)).ok, false);
    }
    assert.equal(received.length, 1);
    await proxy.close();
    assert.deepEqual(received.map(value => value.method), ["echo.ping", "echo.release"]);
    assert.equal(received[1].params.workspace, "/work/selected");
  });
});

test("malformed UTF-8, oversized frames, batches and extra frames never reach upstream", async () => {
  await fixture(async ({ endpoint, received }) => {
    for (const frame of [
      Buffer.from("not JSON\n"), Buffer.from("x".repeat(17000) + "\n"),
      Buffer.concat([Buffer.from('{"id":"'), Buffer.from([0xff]), Buffer.from('","method":"echo.ping","params":{}}\n')]),
      Buffer.from(JSON.stringify([request()]) + "\n"),
      Buffer.from(JSON.stringify(request()) + "\n" + JSON.stringify(request()) + "\n"),
    ]) assert.equal((await exchange(endpoint, frame)).ok, false);
    assert.deepEqual(received, []);
  });
});

for (const [name, respond] of [
  ["rejected acknowledgment", socket => socket.end('{"ok":false}\n')],
  ["missing acknowledgment", socket => socket.end()],
  ["oversized acknowledgment", socket => socket.end("x".repeat(17000) + "\n")],
]) {
  test(`upstream failure denies without forwarding host data: ${name}`, async () => {
    await fixture(async ({ endpoint, received }) => {
      assert.equal((await exchange(endpoint, request())).ok, false);
      assert.equal(received.length, 1);
    }, respond);
  });
}
