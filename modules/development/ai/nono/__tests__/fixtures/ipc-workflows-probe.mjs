import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createConnection } from "node:net";
import { once } from "node:events";
import { createInterface } from "node:readline";

const { upstream, aliases, browser, lightpanda, git, editor, nativeEndpoints = [] } = JSON.parse(process.argv[2]);
function exchange(path, request) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(path);
    let received = "";
    socket.once("error", reject);
    socket.once("connect", () => socket.write(JSON.stringify(request) + "\n"));
    socket.on("data", chunk => {
      received += chunk.toString();
      if (!received.includes("\n")) return;
      socket.destroy();
      resolve(JSON.parse(received));
    });
    socket.setTimeout(3000, () => { socket.destroy(); reject(new Error("Report timed out")); });
  });
}
assert.ok(process.env.HTTP_PROXY, "the credential proxy must remain active");
assert.notEqual(process.env.HERDR_SOCKET_PATH, upstream);
const params = { pane_id: "wFixture:p1", source: "herdr:pi", agent: "pi", state: "idle", seq: 1 };
assert.equal((await exchange(process.env.HERDR_SOCKET_PATH, { id: "ok", method: "pane.report_agent", params })).ok, true);
for (const request of [
  { id: "input", method: "pane.send_input", params: { ...params, text: "id" } },
  { id: "other", method: "pane.report_agent", params: { ...params, pane_id: "wFixture:p2" } },
  { id: "argv", method: "pane.report_agent", params: { ...params, resume_argv: ["sh"] } },
]) assert.equal((await exchange(process.env.HERDR_SOCKET_PATH, request)).ok, false);
for (const path of [upstream, ...aliases, ...nativeEndpoints]) {
  await assert.rejects(exchange(path, { id: "bypass", method: "pane.send_input", params }), error => ["EACCES", "EPERM"].includes(error.code));
}
assert.equal(process.env.PI_LENS_WARM_ATTACH, "0");
if (editor) {
  for (const sessionId of ["first-session", "replacement-session"]) {
    const socket = createConnection(process.env.PI_NVIM_ASK_SOCKET);
    const closed = once(socket, "close");
    const frames = createInterface({ input: socket })[Symbol.asyncIterator]();
    socket.setTimeout(3000, () => socket.destroy(new Error("Pi Ask timed out")));
    try {
      await once(socket, "connect");
      socket.write(JSON.stringify({ version: 1, type: "bind", launchId: process.env.PI_NVIM_LAUNCH_ID, cwd: process.cwd(), sessionId }) + "\n");
      const bound = JSON.parse((await frames.next()).value);
      const prompt = JSON.parse((await frames.next()).value);
      assert.equal(bound.type, "bound");
      assert.equal(bound.binding.sessionId, sessionId);
      assert.equal(prompt.type, "prompt");
      socket.write(JSON.stringify({ version: 1, type: "ack", payload: {
        version: 1, requestId: prompt.request.requestId, launchId: bound.binding.launchId,
        sessionId, ownerId: bound.binding.ownerId, outcome: "accepted", state: "idle",
      } }) + "\n");
      socket.end(JSON.stringify({ version: 1, type: "close" }) + "\n");
      await closed;
    } finally {
      socket.destroy();
      await frames.return();
    }
  }
}
if (git) {
  const run = args => {
    const result = spawnSync(git, args, { encoding: "utf8", timeout: 10000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    return result.stdout;
  };
  try {
    run(["fsmonitor--daemon", "start"]);
    run(["-c", "core.fsmonitor=true", "status", "--porcelain"]);
    run(["fsmonitor--daemon", "status"]);
  } finally {
    const stopped = spawnSync(git, ["fsmonitor--daemon", "stop"], { encoding: "utf8", timeout: 10000 });
    assert.ifError(stopped.error);
    if (stopped.status !== 128 || !/fsmonitor--daemon is not running/.test(stopped.stderr ?? "")) assert.equal(stopped.status, 0, stopped.stderr);
  }
}
if (browser && lightpanda) {
  const args = ["--engine", "lightpanda", "--session", "pi-ipc-test", "--executable-path", lightpanda];
  const run = command => {
    const result = spawnSync(browser, [...args, ...command], { encoding: "utf8", timeout: 20000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    return result.stdout;
  };
  try {
    run(["open", "data:text/html,<html><title>Pi IPC fixture</title><button>Fixture button</button></html>"]);
    assert.match(run(["get", "title"]), /Pi IPC fixture/);
    assert.match(run(["snapshot", "-i"]), /Fixture button/);
  } finally {
    run(["close"]);
  }
}
console.log("IPC workflows verified");
