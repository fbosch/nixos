import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, mkdirSync, rmSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { ensureSshIdentity } from "../scripts/launch/ssh.mts";

const sshAdd = "/nix/store/fixture-openssh/bin/ssh-add";
const environment = { SSH_AUTH_SOCK: "/run/agent.sock", GITHUB_TOKEN: "must-not-leak" };
const created = [];
function fixture(names = ["id_ed25519", "id_rsa"], base = tmpdir()) {
  const home = mkdtempSync(join(base, "pi-ssh-identities-"));
  created.push(home);
  mkdirSync(join(home, ".ssh"));
  for (const name of names) {
    writeFileSync(join(home, ".ssh", name), "fixture", { mode: 0o600 });
    writeFileSync(join(home, ".ssh", `${name}.pub`), "fixture public key");
  }
  return home;
}
function agent(statuses) {
  const calls = [];
  return { calls, run: (binary, args, options) => {
    assert.ok(statuses.length, `Unexpected ssh-add call: ${args.join(" ")}`);
    calls.push({ binary, args, env: options.env, stdio: options.stdio });
    return { status: statuses.shift() };
  } };
}
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });

function ensure(home, mocked, env = environment, options = {}) {
  return ensureSshIdentity(env, home, sshAdd, { run: mocked.run, interactive: true, ...options });
}

test("a loaded ED25519 identity does not prevent loading the missing Azure RSA identity", () => {
  const home = fixture();
  const rsa = join(home, ".ssh", "id_rsa");
  const mocked = agent([0, 0, 1, 0]);
  assert.equal(ensure(home, mocked), "added");
  assert.deepEqual(mocked.calls.map(call => call.args), [
    ["-l"], ["-T", join(home, ".ssh", "id_ed25519.pub")], ["-T", `${rsa}.pub`], [rsa],
  ]);
  for (const call of mocked.calls) {
    assert.equal(call.binary, sshAdd);
    assert.deepEqual(call.env, { SSH_AUTH_SOCK: environment.SSH_AUTH_SOCK, HOME: home });
  }
  assert.equal(mocked.calls.at(-1).stdio, "inherit");
});

test("an empty agent receives both configured identities before confinement", () => {
  const home = fixture();
  const mocked = agent([1, 1, 0, 1, 0]);
  assert.equal(ensure(home, mocked), "added");
  assert.deepEqual(mocked.calls.filter(call => call.args[0] !== "-l" && call.args[0] !== "-T").map(call => call.args), [
    [join(home, ".ssh", "id_ed25519")], [join(home, ".ssh", "id_rsa")],
  ]);
});

test("usable configured identities are not loaded again", () => {
  const home = fixture();
  const mocked = agent([0, 0, 0]);
  assert.equal(ensure(home, mocked), "loaded");
  assert.deepEqual(mocked.calls.map(call => call.args), [
    ["-l"], ["-T", join(home, ".ssh", "id_ed25519.pub")], ["-T", join(home, ".ssh", "id_rsa.pub")],
  ]);
});

test("missing identity files are optional on other hosts", () => {
  const home = fixture(["id_rsa"]);
  const mocked = agent([0, 1, 0]);
  assert.equal(ensure(home, mocked), "added");
  assert.deepEqual(mocked.calls.map(call => call.args), [["-l"], ["-T", join(home, ".ssh", "id_rsa.pub")], [join(home, ".ssh", "id_rsa")]]);
});

test("an identity without a public companion is offered to the host agent", () => {
  const home = fixture(["id_rsa"]);
  unlinkSync(join(home, ".ssh", "id_rsa.pub"));
  const mocked = agent([0, 0]);
  assert.equal(ensure(home, mocked), "added");
  assert.deepEqual(mocked.calls.map(call => call.args), [["-l"], [join(home, ".ssh", "id_rsa")]]);
});

test("failure to load one identity is reported without skipping the other", t => {
  const home = fixture();
  const warning = t.mock.method(console, "warn", () => {});
  const mocked = agent([0, 1, 1, 1, 0]);
  assert.equal(ensure(home, mocked), "failed");
  assert.equal(mocked.calls.at(-1).args[0], join(home, ".ssh", "id_rsa"));
  assert.equal(warning.mock.callCount(), 1);
  assert.match(warning.mock.calls[0].arguments[0], /ssh-add did not load ~\/\.ssh\/id_ed25519/);
});

test("noninteractive, agent-free, unpinned and keyless launches do not load identities", () => {
  const home = fixture();
  for (const [env, binary, options, target] of [
    [environment, sshAdd, { interactive: false }, home],
    [{}, sshAdd, {}, home],
    [environment, "ssh-add", {}, home],
    [environment, undefined, {}, home],
    [environment, sshAdd, {}, join(home, "elsewhere")],
  ]) {
    const mocked = agent([]);
    assert.equal(ensureSshIdentity(env, target, binary, { interactive: true, ...options, run: mocked.run }), "skipped");
    assert.equal(mocked.calls.length, 0);
  }
});

test("an unreachable agent does not trigger a host key load", () => {
  const home = fixture();
  const mocked = agent([2]);
  assert.equal(ensure(home, mocked), "skipped");
  assert.deepEqual(mocked.calls.map(call => call.args), [["-l"]]);
});

const nativeAdd = process.env.SSH_ADD_TEST_BINARY;
const nativeAgent = process.env.SSH_AGENT_TEST_BINARY;
const nativeKeygen = process.env.SSH_KEYGEN_TEST_BINARY;
test("a real host agent receives missing RSA while retaining its loaded ED25519 identity", {
  skip: !nativeAdd || !nativeAgent || !nativeKeygen,
}, () => {
  const home = fixture([], "/tmp");
  const socket = join(home, "agent.sock");
  for (const [name, type] of [["id_ed25519", "ed25519"], ["id_rsa", "rsa"]]) {
    const generated = spawnSync(nativeKeygen, ["-q", "-t", type, "-N", "", "-f", join(home, ".ssh", name)], { env: { HOME: home }, encoding: "utf8", timeout: 10000 });
    assert.ifError(generated.error);
    assert.equal(generated.status, 0, generated.stderr);
  }
  const started = spawnSync(nativeAgent, ["-s", "-a", socket], { env: { HOME: home }, encoding: "utf8", timeout: 5000 });
  assert.ifError(started.error);
  assert.equal(started.status, 0, started.stderr);
  const pid = /SSH_AGENT_PID=(\d+);/.exec(started.stdout);
  assert.ok(pid, started.stdout);
  try {
    const env = { HOME: home, SSH_AUTH_SOCK: socket };
    const loaded = spawnSync(nativeAdd, [join(home, ".ssh", "id_ed25519")], { env, encoding: "utf8", timeout: 5000 });
    assert.equal(loaded.status, 0, loaded.stderr);
    assert.equal(ensureSshIdentity(env, home, nativeAdd, { interactive: true }), "added");
    for (const name of ["id_ed25519", "id_rsa"]) {
      const checked = spawnSync(nativeAdd, ["-T", join(home, ".ssh", `${name}.pub`)], { env, encoding: "utf8", timeout: 5000 });
      assert.equal(checked.status, 0, checked.stderr);
    }
    assert.equal(ensureSshIdentity(env, home, nativeAdd, { interactive: true }), "loaded");
  } finally {
    try { process.kill(Number(pid[1]), "SIGTERM"); }
    catch (error) { if (error.code !== "ESRCH") throw error; }
  }
});
