import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, realpathSync, rmSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { promisify } from "node:util";
import { createReportValidator, defaultReportingCapability } from "../scripts/herdr-protocol.mts";
import { startReportingServer } from "../scripts/herdr-server.mts";

const runFile = promisify(execFile);
const authority = { upstream: "/fixture/host", pane: "wFixture:p1", embedded: false, sessionDirectory: "/fixture/sessions" };
const request = (method = "pane.read", params = {}) => ({ id: "read:1", method, params: method === "pane.read" ? { pane_id: "wFixture:p2", source: "visible", ...params } : params });
const pane = () => ({ pane_id: "wFixture:p2", workspace_id: "wFixture", tab_id: "wFixture:t1", terminal_id: "term_fixture", focused: false, agent_status: "idle", revision: 2, label: "Neighbor æøå", private_field: "not projected" });
const read = () => ({ ...pane(), source: "visible", format: "text", text: "status æøå\n", truncated: false });

function exchange(endpoint, message) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(endpoint);
    const chunks = [];
    socket.once("error", reject);
    socket.setTimeout(3000, () => socket.destroy(new Error("Fixture read timed out")));
    socket.once("connect", () => socket.write(JSON.stringify(message) + "\n"));
    socket.on("data", chunk => {
      chunks.push(chunk);
      if (!chunk.includes(10)) return;
      socket.destroy();
      try { resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))); } catch (error) { reject(error); }
    });
  });
}

async function fixture(run, reply) {
  const root = realpathSync(mkdtempSync("/tmp/pi-hread-"));
  const received = [];
  const peers = new Set();
  const upstream = join(root, "host");
  const endpoint = join(root, "proxy");
  const host = createServer(socket => {
    peers.add(socket);
    socket.on("error", () => {});
    socket.once("close", () => peers.delete(socket));
    let input = "";
    socket.on("data", chunk => {
      input += chunk;
      if (!input.includes("\n")) return;
      const message = JSON.parse(input);
      received.push(message);
      const result = reply?.(message) ?? (message.method === "ping"
        ? { type: "pong", version: "0.9.5", protocol: 22 }
        : message.method === "pane.list" ? { type: "pane_list", panes: [pane()] } : { type: "pane_read", read: read() });
      socket.end(JSON.stringify({ id: message.id, result, host_private_data: "not projected" }) + "\n");
    });
  });
  let proxy;
  try {
    host.listen(upstream);
    await once(host, "listening");
    const capability = { ...defaultReportingCapability, cleanup: [] };
    proxy = await startReportingServer({ ...authority, upstream }, endpoint, capability);
    await run({ endpoint, received, root });
  } finally {
    await proxy?.close();
    for (const peer of peers) peer.destroy();
    await new Promise(resolve => host.close(resolve));
    rmSync(root, { recursive: true, force: true });
  }
}

test("workspace discovery and passive snapshots are launch-bound and bounded", () => {
  const mutable = { ...authority };
  const validate = createReportValidator(mutable);
  mutable.pane = "wOther:p3";
  assert.deepEqual(validate(request("pane.list")).params, { workspace_id: "wFixture" });
  assert.deepEqual(validate(request("pane.list", { workspace_id: "wFixture" })).params, { workspace_id: "wFixture" });
  for (const source of ["visible", "recent", "recent_unwrapped", "detection"]) {
    assert.deepEqual(validate(request("pane.read", { source })).params, { pane_id: "wFixture:p2", source, lines: 120, format: "text", strip_ansi: true });
  }
  assert.equal(validate(request("pane.read", { lines: 200 })).params.lines, 200);
});

test("other workspaces, raw output and every control operation stay rejected", async () => {
  await fixture(async ({ endpoint, received }) => {
    const rejected = [
      request("pane.list", { workspace_id: "wOther" }),
      request("pane.read", { pane_id: "wOther:p2" }),
      request("pane.read", { pane_id: "wFixtureExtra:p2" }),
      request("pane.read", { pane_id: "wFixture:p2/../p1" }),
      request("pane.read", { lines: 0 }), request("pane.read", { lines: 201 }),
      request("pane.read", { format: "ansi" }), request("pane.read", { strip_ansi: false }),
      request("pane.read", { intent: "interactive" }), request("pane.read", { command: "true" }),
      ...["pane.send_input", "pane.send_text", "pane.send_keys", "pane.scroll", "pane.split", "pane.run", "agent.prompt", "agent.read"].map(method => request(method, { pane_id: "wFixture:p2", text: "fixture" })),
      request("pane.report_agent", { pane_id: "wFixture:p2", source: "herdr:pi", agent: "pi", state: "idle" }),
    ];
    for (const message of rejected) {
      const response = await exchange(endpoint, message);
      assert.deepEqual(response, { id: message.id, ok: false, error: { code: "PI_IPC_DENIED", message: "IPC request rejected" } });
    }
    assert.deepEqual(received, []);
  });
});

test("reads return only projected workspace data and strip terminal controls", async () => {
  await fixture(async ({ endpoint, received }) => {
    const listing = await exchange(endpoint, request("pane.list"));
    assert.deepEqual(listing.result, { type: "pane_list", panes: [{ pane_id: "wFixture:p2", workspace_id: "wFixture", tab_id: "wFixture:t1", revision: 2, terminal_id: "term_fixture", focused: false, agent_status: "idle", label: "Neighbor æøå" }] });
    const response = await exchange(endpoint, request());
    assert.deepEqual(response, { id: "read:1", ok: true, result: { type: "pane_read", read: { pane_id: "wFixture:p2", workspace_id: "wFixture", tab_id: "wFixture:t1", revision: 2, source: "visible", format: "text", text: "status æøå\n", truncated: false } } });
    assert.deepEqual(received, [request("pane.list", { workspace_id: "wFixture" }), request("pane.read", { lines: 120, format: "text", strip_ansi: true })]);
  }, message => message.method === "pane.list" ? { type: "pane_list", panes: [pane()] } : { type: "pane_read", read: { ...read(), text: "\u001b]52;c;c2VjcmV0\u0007\u001b[31mstatus æøå\u001b[0m\n" } });
});

for (const [name, result] of [
  ["pane moved to another workspace", { type: "pane_read", read: { ...read(), workspace_id: "wOther", pane_id: "wOther:p2", tab_id: "wOther:t1" } }],
  ["different requested pane", { type: "pane_read", read: { ...read(), pane_id: "wFixture:p3" } }],
  ["different source", { type: "pane_read", read: { ...read(), source: "recent" } }],
  ["raw terminal output", { type: "pane_read", read: { ...read(), format: "ansi" } }],
  ["invalid snapshot", { type: "pane_read", read: null }],
  ["unbounded line count", { type: "pane_read", read: { ...read(), text: "line\n".repeat(201) } }],
  ["oversized response", { type: "pane_read", read: { ...read(), text: "x".repeat(66000) } }],
]) {
  test(`read response fails closed: ${name}`, async () => {
    await fixture(async ({ endpoint }) => assert.equal((await exchange(endpoint, request())).error.code, "PI_IPC_DENIED"), () => result);
  });
}

test("discovery cannot return panes from another workspace", async () => {
  await fixture(async ({ endpoint }) => assert.equal((await exchange(endpoint, request("pane.list"))).error.code, "PI_IPC_DENIED"),
    () => ({ type: "pane_list", panes: [pane(), { ...pane(), workspace_id: "wOther", pane_id: "wOther:p1", tab_id: "wOther:t1" }] }));
});

test("pinned Herdr CLI lists and reads through the broker, but cannot send input", { skip: !process.env.HERDR_READ_TEST_BINARY }, async () => {
  await fixture(async ({ endpoint, root, received }) => {
    const options = { env: { HOME: root, HERDR_ENV: "1", HERDR_SOCKET_PATH: endpoint, HERDR_PANE_ID: authority.pane }, timeout: 5000 };
    const listed = await runFile(process.env.HERDR_READ_TEST_BINARY, ["pane", "list"], options);
    assert.equal(JSON.parse(listed.stdout).result.panes[0].pane_id, "wFixture:p2");
    const captured = await runFile(process.env.HERDR_READ_TEST_BINARY, ["pane", "read", "wFixture:p2", "--source", "visible", "--lines", "10"], options);
    assert.equal(captured.stdout, "status æøå\n");
    await assert.rejects(runFile(process.env.HERDR_READ_TEST_BINARY, ["pane", "send-text", "wFixture:p2", "never forwarded"], options), error => {
      assert.equal(error.code, 1);
      assert.match(error.stdout + error.stderr, /PI_IPC_DENIED/);
      return true;
    });
    assert.deepEqual(received.map(message => message.method), ["ping", "pane.list", "ping", "pane.read", "ping"]);
  });
});
