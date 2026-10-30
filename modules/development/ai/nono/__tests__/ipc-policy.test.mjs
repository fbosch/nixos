import assert from "node:assert/strict";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { defaultCapabilities, createMessageValidator, endpointArguments, loadCapabilities, selectCapabilities, validateCapabilities } from "../scripts/ipc-policy.mjs";
import { launchArguments } from "../scripts/launcher.mjs";
import { withHerdrReporter } from "../scripts/herdr-bootstrap.mjs";

const roots = [];
function fixture() {
  const root = realpathSync(mkdtempSync("/tmp/pi-cap-"));
  roots.push(root);
  return root;
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
const registry = () => structuredClone(defaultCapabilities);
const selected = (value = defaultCapabilities) => selectCapabilities(value, "restricted", "linux");

test("profile selection preserves ordinary grants and explicitly selects restricted authority", () => {
  assert.deepEqual(Object.keys(selectCapabilities(defaultCapabilities, "ordinary", "linux")), []);
  assert.equal(selectCapabilities(defaultCapabilities, "ordinary", "darwin")["git-fsmonitor"].access, "connect-existing");
  assert.equal(selected()["git-fsmonitor"].access, "bind");
  assert.equal(selected()["git-fsmonitor"].authority, "full-protocol");
  assert.equal(selected()["herdr-reporting"].backend, "json-lines");
  assert.throws(() => selectCapabilities(defaultCapabilities, "missing"), /Unknown IPC profile/);
  assert.ok(Object.isFrozen(defaultCapabilities.capabilities["herdr-reporting"].operations));
});

for (const [name, change] of [
  ["version", value => { value.version = 2; }],
  ["unknown root field", value => { value.command = "id"; }],
  ["unknown capability", value => { value.profiles.restricted.missing = {}; }],
  ["unknown backend", value => { value.capabilities["git-fsmonitor"].backend = "shell"; }],
  ["unknown provider", value => { value.capabilities["herdr-reporting"].provider = "shell"; }],
  ["wrong Herdr socket export", value => { value.capabilities["herdr-reporting"].socketEnvironment = "OTHER_SOCKET"; }],
  ["duplicate socket exports", value => { value.capabilities.second = structuredClone(value.capabilities["herdr-reporting"]); value.profiles.restricted.second = {}; }],
  ["endpoint traversal", value => { value.capabilities["git-fsmonitor"].filename = "../other.sock"; }],
  ["endpoint selection mismatch", value => { value.profiles.restricted["git-fsmonitor"] = {}; }],
  ["filter selection mismatch", value => { value.profiles.restricted["herdr-reporting"] = { access: "bind", platforms: ["linux"] }; }],
  ["unbounded clients", value => { value.capabilities["herdr-reporting"].limits.maxConnections = 100000; }],
  ["unknown limit", value => { value.capabilities["herdr-reporting"].limits.fallback = true; }],
  ["open parameter schema", value => { value.capabilities["herdr-reporting"].operations["pane.report_agent"].schema.additionalProperties = true; }],
  ["unknown schema keyword", value => { value.capabilities["herdr-reporting"].operations["pane.report_agent"].schema.executable = "id"; }],
  ["unknown binding property", value => { value.capabilities["herdr-reporting"].operations["pane.report_agent"].bindings.extra = "pane"; }],
  ["unknown cleanup operation", value => { value.capabilities["herdr-reporting"].cleanup[0].method = "pane.send_input"; }],
  ["unknown cleanup binding", value => { value.capabilities["herdr-reporting"].cleanup[0].optionalBindings = ["command"]; }],
  ["async schema", value => { value.capabilities["herdr-reporting"].operations["pane.report_agent"].schema.$async = true; }],
]) {
  test(`invalid manifests fail closed: ${name}`, () => {
    const value = registry();
    change(value);
    assert.throws(() => validateCapabilities(value));
  });
}

test("invalid JSON reports its manifest path and never becomes an empty policy", () => {
  const path = join(fixture(), "invalid.json");
  writeFileSync(path, "{");
  assert.throws(() => loadCapabilities(path), /Cannot read IPC capability manifest/);
});

test("lazy endpoint grants cover selected metadata only, without directory grants", () => {
  const root = fixture();
  const git = join(root, "git");
  const unrelated = join(root, "other");
  mkdirSync(git); mkdirSync(unrelated);
  assert.deepEqual(endpointArguments(selected(), { "selected-git-metadata": [git, git] }), ["--allow-unix-socket-bind", join(git, "fsmonitor--daemon.ipc")]);
  assert.deepEqual(endpointArguments(selectCapabilities(defaultCapabilities, "ordinary", "darwin"), { "selected-git-metadata": [git] }), []);
});

test("direct endpoint grants accept existing owned sockets and reject aliases", async () => {
  const root = fixture();
  const git = join(root, "git"); mkdirSync(git);
  const endpoint = join(git, "fsmonitor--daemon.ipc");
  const host = createServer();
  host.listen(endpoint); await once(host, "listening");
  try {
    assert.deepEqual(endpointArguments(selectCapabilities(defaultCapabilities, "ordinary", "darwin"), { "selected-git-metadata": [git] }), ["--allow-unix-socket", endpoint]);
  } finally { await new Promise(resolve => host.close(resolve)); }
  const target = join(root, "other"); writeFileSync(target, "not a socket");
  symlinkSync(target, endpoint);
  assert.throws(() => endpointArguments(selected(), { "selected-git-metadata": [git] }), /Unsafe IPC endpoint/);
  assert.deepEqual(endpointArguments(selectCapabilities(defaultCapabilities, "ordinary", "darwin"), { "selected-git-metadata": [git] }), []);
});

test("the launcher uses registry selection rather than hard-coded fsmonitor grants", () => {
  const root = fixture();
  const home = join(root, "home"); const cwd = join(root, "work"); const agent = join(home, ".pi", "agent");
  mkdirSync(agent, { recursive: true }); mkdirSync(join(cwd, ".git"), { recursive: true });
  const profile = join(root, "profile.json"); const raw = join(root, "pi");
  writeFileSync(profile, JSON.stringify({ linux: { af_unix_mediation: "pathname" } })); writeFileSync(raw, "fixture");
  const args = value => launchArguments(cwd, agent, home, {}, profile, raw, process.env.ENV_TEST_BINARY ?? "/usr/bin/env", "linux", value);
  const path = join(cwd, ".git", "fsmonitor--daemon.ipc");
  assert.ok(args(defaultCapabilities).includes(path));
  const disabled = registry(); delete disabled.profiles.restricted["git-fsmonitor"];
  assert.ok(!args(validateCapabilities(disabled)).includes(path));
});

test("bindings capture trusted context and UTF-8 limits apply to bytes", () => {
  const capability = selected()["herdr-reporting"];
  const context = { pane: "wFixture:p1", source: "herdr:pi", agent: "pi", titleSource: "user:pi-session-title" };
  const validate = createMessageValidator(capability, context);
  const request = message => ({ id: 1, method: "pane.report_agent", params: { pane_id: "wFixture:p1", source: "herdr:pi", agent: "pi", state: "idle", message } });
  context.pane = "other";
  assert.equal(validate(request("æ".repeat(512))).params.pane_id, "wFixture:p1");
  assert.throws(() => validate(request("æ".repeat(513))));
  assert.throws(() => validate(request("bad\ud800")));
  assert.throws(() => validate(request("bad\u0085")));
  assert.throws(() => validate({ ...request("ok"), params: { ...request("ok").params, pane_id: "other" } }), /identity mismatch/);
  const session = { ...request("ok"), params: { ...request("ok").params, agent_session_id: "019a3741-a34c-7000-81e7-111111111111" } };
  assert.equal(validate(session).params.agent_session_id, session.params.agent_session_id);
  assert.throws(() => validate({ ...session, params: { ...session.params, agent_session_id: session.params.agent_session_id + "\n" } }));
  assert.throws(() => createMessageValidator(capability, {}), /Missing IPC launch binding/);
});

test("disabling restricted reporting removes inherited raw control access", async () => {
  const environment = { HERDR_ENV: "1", HERDR_SOCKET_PATH: "/host/control", HERDR_PANE_ID: "wFixture:p1", PI_NVIM_HERDR_PANE_ID: "wFixture:p1", HERDR_AGENT: "pi" };
  await withHerdrReporter(environment, environment, fixture(), "/", "/", [], bound => {
    for (const key of Object.keys(environment)) assert.equal(bound[key], undefined);
  }, null);
});
