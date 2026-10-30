import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { createInterface } from "node:readline";
import {
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  statSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { createConnection } from "node:net";

const script = fileURLToPath(new URL("../scripts/pi-ask.lua", import.meta.url));
const harness = fileURLToPath(new URL("./pi-ask-host.lua", import.meta.url));
const cwd = resolve(new URL("../../../../..", import.meta.url).pathname);

function storePath(path) {
  const result = spawnSync("nix-store", ["--add", path], { encoding: "utf8" });
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const stored = result.stdout.trim();
  assert.match(stored, /^\/nix\/store\//);
  assert.equal(lstatSync(stored).isSymbolicLink(), false);
  return stored;
}

function eventQueue(child) {
  const queue = [];
  const waiters = [];
  let failure;
  const lines = createInterface({ input: child.stdout });
  lines.on("line", (line) => {
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      failure = new Error(`Unexpected Neovim output: ${line}`);
      while (waiters.length) waiters.shift()?.reject(failure);
      return;
    }
    const waiter = waiters.findIndex((entry) => entry.predicate(event));
    if (waiter >= 0) waiters.splice(waiter, 1)[0]?.resolve(event);
    else queue.push(event);
  });
  child.once("exit", (code) => {
    if (code !== 0) {
      failure = new Error(`Neovim helper exited ${code}`);
      while (waiters.length) waiters.shift()?.reject(failure);
    }
  });
  return {
    close: () => lines.close(),
    next(predicate, timeoutMs = 5000) {
      if (failure) return Promise.reject(failure);
      const index = queue.findIndex(predicate);
      if (index >= 0) return Promise.resolve(queue.splice(index, 1)[0]);
      return new Promise((resolve, reject) => {
        const waiter = { predicate, resolve, reject };
        waiters.push(waiter);
        const timer = setTimeout(() => {
          const i = waiters.indexOf(waiter);
          if (i >= 0) waiters.splice(i, 1);
          reject(new Error("Timed out waiting for Neovim helper event"));
        }, timeoutMs);
        const originalResolve = waiter.resolve;
        waiter.resolve = (event) => {
          clearTimeout(timer);
          originalResolve(event);
        };
      });
    },
  };
}

function connect(path) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(path);
    const frames = [];
    const waiters = [];
    let buffer = "";
    socket.setEncoding("utf8");
    socket.on("data", (chunk) => {
      buffer += chunk;
      while (true) {
        const newline = buffer.indexOf("\n");
        if (newline < 0) break;
        const frame = JSON.parse(buffer.slice(0, newline));
        buffer = buffer.slice(newline + 1);
        const waiter = waiters.shift();
        if (waiter) waiter(frame);
        else frames.push(frame);
      }
    });
    socket.once("error", (error) => reject(error));
    socket.once("connect", () => resolve({
      socket,
      closed: once(socket, "close"),
      send(value) { socket.write(`${JSON.stringify(value)}\n`); },
      sendRaw(value) { socket.write(value); },
      next() {
        const frame = frames.shift();
        if (frame !== undefined) return Promise.resolve(frame);
        return new Promise((resolveFrame, rejectFrame) => {
          const timer = setTimeout(() => rejectFrame(new Error("Timed out waiting for socket frame")), 5000);
          waiters.push((value) => { clearTimeout(timer); resolveFrame(value); });
        });
      },
    }));
  });
}

async function rejectsMessage(path, value) {
  const client = await connect(path);
  client.send(value);
  const response = await client.next();
  assert.deepEqual(response, { version: 1, type: "error", code: "protocol-error" });
  await client.closed;
}

test("production Pi Ask helper enforces NDJSON and private socket lifecycle", { timeout: 30000 }, async (t) => {
  const nvim = spawnSync("nvim", ["--version"], { encoding: "utf8" });
  const nixStore = spawnSync("nix-store", ["--version"], { encoding: "utf8" });
  if (nvim.status !== 0 || nixStore.status !== 0) {
    t.skip("requires Nix and headless Neovim");
    return;
  }

  const storedHelper = storePath(script);
  const storedHarness = storePath(harness);
  const root = mkdtempSync(join("/tmp", "piask-"));
  const home = join(root, "home");
  mkdirSync(home, { mode: 0o700 });
  const child = spawn("nvim", ["--headless", "-u", "NONE", "-l", storedHarness], {
    cwd,
    env: {
      ...process.env,
      HOME: home,
      PI_ASK_TEST_HOST: storedHelper,
      PI_ASK_TEST_CWD: cwd,
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
  const events = eventQueue(child);
  let exited = false;
  const childExited = once(child, "exit");
  try {
    const ready = await events.next((event) => event.event === "ready");
    const socketPath = ready.socketPath;
    assert.equal(socketPath.length <= 103, true);
    const privateRoot = dirname(dirname(socketPath));
    const privateSocketDir = dirname(socketPath);
    for (const directory of [privateRoot, privateSocketDir]) {
      const stat = statSync(directory);
      assert.equal(stat.uid, process.getuid());
      assert.equal(stat.mode & 0o777, 0o700);
    }
    assert.equal(statSync(socketPath).mode & 0o777, 0o600);

    await rejectsMessage(socketPath, {
      version: 1, type: "bind", launchId: "0123456789abcdef0123456789abcdef",
      cwd, sessionId: "unknown-fields", extra: true,
    });
    await rejectsMessage(socketPath, {
      version: 1, type: "nvim_exec_lua", code: "return os.execute('false')",
    });
    const oversized = await connect(socketPath);
    oversized.sendRaw("x".repeat(70 * 1024));
    const oversizedResponse = await oversized.next();
    assert.deepEqual(oversizedResponse, { version: 1, type: "error", code: "protocol-error" });
    await oversized.closed;

    await rejectsMessage(socketPath, {
      version: 1, type: "bind", launchId: "0123456789abcdef0123456789abcdef",
      cwd: cwd + "-other", sessionId: "wrong-worktree",
    });

    for (const sessionId of ["first-session", "replacement-session"]) {
      const client = await connect(socketPath);
      client.send({
        version: 1, type: "bind", launchId: "0123456789abcdef0123456789abcdef", cwd, sessionId,
      });
      const bound = await client.next();
      assert.equal(bound.type, "bound");
      assert.deepEqual(Object.keys(bound).sort(), ["binding", "type", "version"]);
      assert.equal(bound.binding.sessionId, sessionId);
      assert.equal(bound.binding.cwd, cwd);
      const prompt = await client.next();
      assert.equal(prompt.type, "prompt");
      assert.deepEqual(Object.keys(prompt).sort(), ["request", "type", "version"]);
      client.send({
        version: 1,
        type: "ack",
        payload: {
          version: 1,
          requestId: `ack:${sessionId}`,
          launchId: "0123456789abcdef0123456789abcdef",
          sessionId,
          ownerId: "test-owner",
          outcome: "accepted",
          state: "idle",
        },
      });
      const acknowledged = await events.next((event) => event.event === "ack" && event.payload.sessionId === sessionId);
      assert.equal(acknowledged.channelId, bound.binding.channelId);
      client.send({ version: 1, type: "close" });
      const closed = await events.next((event) => event.event === "closed" && event.channelId === bound.binding.channelId);
      assert.equal(closed.channelId, bound.binding.channelId);
      await client.closed;
    }

    const done = await events.next((event) => event.event === "done");
    assert.deepEqual(
      { bindCount: done.bindCount, ackCount: done.ackCount, closeCount: done.closeCount },
      { bindCount: 2, ackCount: 2, closeCount: 2 },
    );
    const [code] = await childExited;
    exited = true;
    assert.equal(code, 0, stderr);
    assert.equal(existsSync(socketPath), false);
    assert.equal(existsSync(privateSocketDir), false);
  } finally {
    if (!exited && child.exitCode === null && child.signalCode === null) {
      child.kill("SIGTERM");
      await childExited;
    }
    events.close();
    rmSync(root, { recursive: true, force: true });
  }
});
