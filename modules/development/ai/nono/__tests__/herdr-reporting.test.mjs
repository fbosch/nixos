import assert from "node:assert/strict";
import { once } from "node:events";
import { linkSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { pathToFileURL } from "node:url";
import { validateReport } from "../scripts/herdr-protocol.mts";
import { startReportingServer } from "../scripts/herdr-server.mts";
import { withHerdrReporter } from "../scripts/herdr-bootstrap.mjs";
import { assertPrivateIpcGrants } from "../scripts/private-ipc.mjs";

const created = [];
function fixture(embedded = false) {
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-report-")));
  created.push(root);
  const home = join(root, "home");
  const sessionDirectory = join(home, ".pi", "agent", "sessions", "fixture");
  mkdirSync(sessionDirectory, { recursive: true });
  const id = "019a3741-a34c-7000-81e7-111111111111";
  const path = join(sessionDirectory, `2026-10-30T10-00-00-000Z_${id}.jsonl`);
  writeFileSync(path, "fixture");
  const authority = { pane: "wFixture:p1", embedded, sessionDirectory, upstream: join(root, "host.sock") };
  const identity = { pane_id: authority.pane, agent: embedded ? "neovim-pi" : "pi", source: embedded ? "custom:neovim-pi" : "herdr:pi" };
  const request = (method = "pane.report_agent", extra = {}) => ({ id: "fixture:1", method, params: { ...identity, seq: 1, ...(method === "pane.report_agent" ? { state: "idle" } : {}), ...extra } });
  return { root, home, id, path, authority, identity, request };
}
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });

function exchange(path, value) {
  return new Promise((resolve, reject) => {
    const socket = createConnection(path);
    let input = "";
    socket.on("error", reject);
    socket.on("connect", () => socket.write(typeof value === "string" ? value : JSON.stringify(value) + "\n"));
    socket.on("data", chunk => {
      input += chunk.toString();
      if (!input.includes("\n")) return;
      socket.destroy();
      try { resolve(JSON.parse(input)); } catch (error) { reject(error); }
    });
    socket.setTimeout(3000, () => { socket.destroy(); reject(new Error("Fixture report timed out")); });
  });
}

for (const embedded of [false, true]) {
  test(`validates lifecycle, references, titles and cleanup for ${embedded ? "embedded" : "standalone"} Pi`, () => {
    const f = fixture(embedded);
    assert.deepEqual(validateReport(f.request(), f.authority), f.request());
    for (const state of ["working", "blocked", "idle"]) {
      assert.equal(validateReport(f.request("pane.report_agent", { state, message: "Waiting for user" }), f.authority).params.state, state);
    }
    for (const reference of [{ agent_session_id: f.id }, { agent_session_path: f.path }]) {
      assert.deepEqual(validateReport(f.request("pane.report_agent_session", { ...reference, session_start_source: "reload" }), f.authority).params, { ...f.identity, seq: 1, ...reference, session_start_source: "reload" });
    }
    for (const title of ["Session æøå", null]) {
      const metadata = f.request("pane.report_metadata", {
        source: "user:pi-session-title", applies_to_source: f.identity.source, tokens: { pi_session_title: title },
        ...(embedded ? title === null ? { clear_display_agent: true } : { display_agent: "Pi" } : {}),
      });
      assert.deepEqual(validateReport(metadata, f.authority), metadata);
    }
    assert.deepEqual(validateReport(f.request("pane.release_agent"), f.authority), f.request("pane.release_agent"));
  });
}

test("rejects other-pane reporting, terminal operations and unauthorized reporting fields", () => {
  const f = fixture();
  for (const value of [
    f.request("pane.send_input", { text: "id\n" }),
    f.request("pane.report_agent", { pane_id: "wFixture:p2" }),
    f.request("pane.report_agent", { agent: "claude" }),
    f.request("pane.report_agent", { source: "custom:other" }),
    f.request("pane.report_agent", { resume_argv: ["sh", "-c", "id"] }),
    f.request("pane.report_agent", { state: "arbitrary" }),
    f.request("pane.report_agent", { message: "bad\u001b]52;" }),
    f.request("pane.report_agent", { seq: -1 }),
    f.request("pane.report_agent_session"),
    f.request("pane.report_agent_session", { agent_session_id: "--print" }),
    f.request("pane.report_agent_session", { agent_session_id: f.id, session_start_source: "shell" }),
    f.request("pane.report_agent_session", { agent_session_id: f.id, agent_session_path: f.path }),
    f.request("pane.report_metadata", { source: "user:pi-session-title", applies_to_source: f.identity.source, tokens: { pi_session_title: "ok", other: "no" } }),
    f.request("pane.report_metadata", { source: "user:pi-session-title", applies_to_source: "other", tokens: { pi_session_title: "ok" } }),
    f.request("pane.report_metadata", { source: "user:pi-session-title", applies_to_source: f.identity.source, tokens: { pi_session_title: "x".repeat(1025) } }),
    { ...f.request(), command: "id" },
  ]) assert.throws(() => validateReport(value, f.authority), undefined, JSON.stringify(value));
});

test("session references reject traversal, outside directories, symlinks and hard links", () => {
  const f = fixture();
  const other = join(f.root, "other");
  mkdirSync(other);
  const name = f.path.split("/").at(-1);
  const target = join(other, name);
  writeFileSync(target, "host-owned fixture");
  const assertRejected = path => assert.throws(() => validateReport(f.request("pane.report_agent_session", { agent_session_path: path }), f.authority));
  assertRejected(target);
  assertRejected(`../${name}`);
  assertRejected(join(f.authority.sessionDirectory, "sub") + `/../${name}`);
  rmSync(f.path);
  symlinkSync(target, f.path);
  assertRejected(f.path);
  rmSync(f.path);
  linkSync(target, f.path);
  assertRejected(f.path);
});

test("the reporting endpoint forwards only validated messages and clears its own state", async () => {
  const f = fixture();
  const received = [];
  const host = createServer(socket => socket.on("data", chunk => {
    received.push(JSON.parse(chunk.toString()));
    socket.end('{"ok":true,"unrelated_host_data":"not forwarded"}\n');
  }));
  let reporter;
  try {
    host.listen(f.authority.upstream);
    await once(host, "listening");
    const path = join(f.root, "report.sock");
    reporter = await startReportingServer(f.authority, path);
    assert.deepEqual(await exchange(path, f.request()), { id: "fixture:1", ok: true });
    assert.deepEqual(received, [f.request()]);
    for (const payload of [f.request("pane.send_input"), f.request("pane.report_agent", { resume_argv: ["pi"] }), "x".repeat(17000) + "\n"]) {
      assert.equal((await exchange(path, payload)).ok, false);
    }
    assert.equal(received.length, 1);
    await reporter.close();
    reporter = undefined;
    assert.equal(received[1].method, "pane.release_agent");
    assert.equal(received[2].params.tokens.pi_session_title, null);
    assert.ok(received.every(value => value.params.pane_id === f.authority.pane));
  } finally {
    await reporter?.close();
    await new Promise(resolve => host.close(resolve));
  }
});

test("shutdown drains accepted reports before clearing their state", async () => {
  const f = fixture();
  const received = [];
  let firstPeer;
  let reply;
  const host = createServer(socket => socket.on("data", chunk => {
    received.push(JSON.parse(chunk.toString()));
    if (received.length === 1) {
      firstPeer = socket;
      reply = () => socket.end('{"ok":true}\n');
      host.emit("accepted");
    } else socket.end('{"ok":true}\n');
  }));
  let reporter;
  let client;
  try {
    host.listen(f.authority.upstream);
    await once(host, "listening");
    const endpoint = join(f.root, "report.sock");
    reporter = await startReportingServer(f.authority, endpoint);
    const accepted = once(host, "accepted");
    client = createConnection(endpoint);
    const disconnected = once(client, "close");
    client.on("error", () => {});
    client.on("connect", () => client.write(JSON.stringify(f.request()) + "\n"));
    await accepted;
    let closed = false;
    const closing = reporter.close().then(() => { closed = true; });
    await disconnected;
    assert.equal(closed, false, "cleanup completed while an upstream report was still pending");
    reply();
    await closing;
    assert.deepEqual(received.map(value => value.method), ["pane.report_agent", "pane.release_agent", "pane.report_metadata"]);
  } finally {
    reply?.();
    client?.destroy();
    firstPeer?.destroy();
    await reporter?.close();
    await new Promise(resolve => host.close(resolve));
  }
});

for (const source of ["global", "project"]) {
  test(`bootstrap reports invalid ${source} settings without launching Pi`, async () => {
    const f = fixture();
    const cwd = join(f.root, "work");
    const agentDir = join(f.home, ".pi", "agent");
    mkdirSync(join(cwd, ".pi"), { recursive: true });
    const settings = join(source === "global" ? agentDir : join(cwd, ".pi"), "settings.json");
    writeFileSync(settings, "{");
    const environment = { HERDR_ENV: "1", HERDR_PANE_ID: f.authority.pane, HERDR_SOCKET_PATH: f.authority.upstream };
    const host = createServer();
    try {
      host.listen(f.authority.upstream);
      await once(host, "listening");
      await assert.rejects(
        withHerdrReporter(environment, environment, f.home, cwd, agentDir, [], async () => assert.fail("Malformed settings must not launch Pi")),
        error => {
          assert.equal(error.message, `Invalid Pi settings JSON: ${settings}`);
          assert.ok(error.cause instanceof SyntaxError);
          return true;
        },
      );
    } finally {
      await new Promise(resolve => host.close(resolve));
    }
  });
}

for (const source of ["global", "project", "environment", "cli", "file"]) {
  test(`bootstrap scopes session references to the ${source} session-directory selection`, async () => {
    const f = fixture();
    const cwd = join(f.root, "work");
    const agentDir = join(f.home, ".pi", "agent");
    mkdirSync(join(cwd, ".pi"), { recursive: true });
    const directories = Object.fromEntries(["global", "project", "environment", "cli", "file"].map(name => [name, join(f.root, name)]));
    for (const path of Object.values(directories)) mkdirSync(path);
    writeFileSync(join(agentDir, "settings.json"), JSON.stringify(source === "file" ? {} : { sessionDir: directories.global }));
    if (["project", "environment", "cli"].includes(source)) writeFileSync(join(cwd, ".pi", "settings.json"), JSON.stringify({ sessionDir: "../project" }));
    const selectedPath = join(directories[source], f.path.split("/").at(-1));
    writeFileSync(selectedPath, "fixture");
    const environment = {
      HERDR_ENV: "1", HERDR_PANE_ID: f.authority.pane, HERDR_SOCKET_PATH: f.authority.upstream,
      ...(["environment", "cli"].includes(source) ? { PI_CODING_AGENT_SESSION_DIR: directories.environment } : {}),
    };
    const args = source === "cli" ? ["--session-dir", "../cli"] : source === "file" ? ["--session", "../file/" + selectedPath.split("/").at(-1)] : [];
    const host = createServer(socket => socket.on("data", () => socket.end('{"ok":true}\n')));
    try {
      host.listen(f.authority.upstream);
      await once(host, "listening");
      await withHerdrReporter(environment, environment, f.home, cwd, agentDir, args, async bound => {
        const response = await exchange(bound.HERDR_SOCKET_PATH, f.request("pane.report_agent_session", { agent_session_path: selectedPath }));
        assert.equal(response.ok, true);
      });
    } finally {
      await new Promise(resolve => host.close(resolve));
    }
  });
}

test("bootstrap binds inherited identity, creates the endpoint before launch and cleans it", async () => {
  const f = fixture();
  const host = createServer(socket => socket.on("data", () => socket.end('{"ok":true}\n')));
  let endpoint;
  try {
    host.listen(f.authority.upstream);
    await once(host, "listening");
    const inherited = { HERDR_ENV: "1", HERDR_PANE_ID: f.authority.pane, HERDR_SOCKET_PATH: f.authority.upstream };
    await withHerdrReporter({ ...inherited, HERDR_PANE_ID: "wOther:p2", HERDR_WORKSPACE_ID: "wOther" }, inherited, f.home, f.root, join(f.home, ".pi", "agent"), ["--session-dir", f.authority.sessionDirectory], async environment => {
      endpoint = environment.HERDR_SOCKET_PATH;
      assert.notEqual(endpoint, f.authority.upstream);
      assert.equal(environment.HERDR_PANE_ID, f.authority.pane);
      assert.equal(environment.HERDR_WORKSPACE_ID, "wFixture");
      assert.equal((await exchange(endpoint, f.request())).ok, true);
      assert.equal((await exchange(endpoint, f.request("pane.report_agent", { pane_id: "wOther:p2" }))).ok, false);
    });
    assert.throws(() => realpathSync(endpoint), /ENOENT/);
    assert.throws(() => assertPrivateIpcGrants([], f.home, f.home), /covers private Pi IPC state/);
  } finally {
    await new Promise(resolve => host.close(resolve));
  }
});

test("bootstrap accepts Herdr's alphanumeric pane suffixes and rejects malformed pane identities", async () => {
  const f = fixture();
  const host = createServer(socket => socket.on("data", () => socket.end('{"ok":true}\n')));
  const launch = pane => withHerdrReporter({}, { HERDR_ENV: "1", HERDR_PANE_ID: pane, HERDR_SOCKET_PATH: f.authority.upstream },
    f.home, f.root, join(f.home, ".pi", "agent"), ["--session-dir", f.authority.sessionDirectory], async environment => environment.HERDR_PANE_ID);
  try {
    host.listen(f.authority.upstream);
    await once(host, "listening");
    assert.equal(await launch("w1F:pN"), "w1F:pN");
    for (const pane of ["w1F:p", "w1F:pN/x", "w1F:pN\n", "w1F", "../p1"]) {
      await assert.rejects(launch(pane), /Invalid inherited Herdr pane identity/, JSON.stringify(pane));
    }
  } finally {
    await new Promise(resolve => host.close(resolve));
  }
});

test("pinned generated Herdr reporter remains compatible with the restricted endpoint", { skip: !process.env.HERDR_REPORTER_TEST_SOURCE }, async () => {
  const f = fixture();
  const received = [];
  const host = createServer(socket => socket.on("data", chunk => {
    const request = JSON.parse(chunk.toString());
    received.push(request);
    socket.end('{"ok":true}\n');
    if (received.length === 2) host.emit("reports");
  }));
  const previous = { ...process.env };
  let reporter;
  try {
    host.listen(f.authority.upstream);
    await once(host, "listening");
    const endpoint = join(f.root, "report.sock");
    reporter = await startReportingServer(f.authority, endpoint);
    Object.assign(process.env, { HERDR_ENV: "1", HERDR_PANE_ID: f.authority.pane, HERDR_SOCKET_PATH: endpoint });
    const generated = await import(pathToFileURL(process.env.HERDR_REPORTER_TEST_SOURCE).href + `?fixture=${Date.now()}`);
    const handlers = new Map();
    generated.default({ on: (name, callback) => handlers.set(name, callback), events: { on() {} } });
    const done = once(host, "reports");
    await handlers.get("session_start")({ reason: "startup" }, {
      mode: "tui", isIdle: () => true, sessionManager: { getSessionId: () => f.id, getSessionFile: () => f.path },
    });
    await done;
    assert.deepEqual(received.map(value => value.method), ["pane.report_agent_session", "pane.report_agent"]);
    assert.equal(received[0].params.agent_session_path, f.path);
    assert.equal(received[1].params.state, "idle");
  } finally {
    process.env = previous;
    await reporter?.close();
    await new Promise(resolve => host.close(resolve));
  }
});
