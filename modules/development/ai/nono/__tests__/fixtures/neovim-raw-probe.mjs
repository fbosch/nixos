import assert from "node:assert/strict";
import { createConnection } from "node:net";
import { once } from "node:events";
import { createInterface } from "node:readline";

assert.equal(process.env.PI_NONO_MODE, "disabled");
assert.equal(process.env.PI_NVIM_SOCKET, undefined);
assert.equal(process.env.PI_MODEL_EXECUTOR_SOCKET, undefined);
for (const sessionId of ["first-session", "replacement-session"]) {
  const socket = createConnection(process.env.PI_NVIM_ASK_SOCKET);
  const closed = once(socket, "close");
  const frames = createInterface({ input: socket })[Symbol.asyncIterator]();
  socket.setTimeout(5000, () => socket.destroy(new Error("Pi Ask timed out")));
  const send = (id, method, params) => socket.write(JSON.stringify({ id, method, params }) + "\n");
  await once(socket, "connect");
  send("bind", "neovim.bind", { launchId: process.env.PI_NVIM_LAUNCH_ID, cwd: process.cwd(), sessionId });
  const bound = JSON.parse((await frames.next()).value);
  const prompt = JSON.parse((await frames.next()).value);
  assert.equal(bound.ok, true);
  assert.equal(bound.result.sessionId, sessionId);
  assert.equal(prompt.params.text, "explain æøå");
  send("ack", "neovim.ack", { payload: {
    version: 1, requestId: prompt.params.requestId, launchId: bound.result.launchId,
    sessionId, ownerId: bound.result.ownerId, outcome: "accepted", state: "idle",
  } });
  assert.equal(JSON.parse((await frames.next()).value).ok, true);
  send("close", "neovim.close", {});
  if (sessionId === "first-session") assert.equal(JSON.parse((await frames.next()).value).ok, true);
  socket.end();
  await closed;
  await frames.return();
}
console.log("Raw editor broker verified");
