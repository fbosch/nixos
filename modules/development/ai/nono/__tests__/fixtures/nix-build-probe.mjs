import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";

const env = { ...process.env, NIX_REMOTE: "daemon" };
assert.notEqual(process.getuid(), 0);
assert.match(readFileSync("/proc/self/status", "utf8"), /^NoNewPrivs:\s+1$/m);

function run(command, args) {
  const result = spawnSync(command, args, { env, encoding: "utf8", timeout: 60000 });
  assert.ifError(result.error);
  assert.equal(result.signal, null, result.stderr);
  return result;
}
const info = run("nix", ["store", "info", "--json"]);
assert.equal(info.status, 0, info.stderr);
assert.equal(JSON.parse(info.stdout).trusted, false);

const build = (name, extra = []) => run("nix", [
  "build", "--impure", "--no-link", "--json", "--file", "/etc/pi-build-test.nix",
  "--argstr", "name", name, ...extra,
]);
for (const [name, options] of [
  ["pi-build-normal", []],
  ["pi-build-sandbox-override", ["--option", "sandbox", "false", "--option", "sandbox-fallback", "true"]],
  ["pi-build-remote-override", ["--builders", "ssh-ng://127.0.0.1:1"]],
]) {
  const result = build(name, options);
  assert.equal(result.status, 0, result.stderr);
  const output = JSON.parse(result.stdout)[0].outputs.out;
  assert.equal(readFileSync(output, "utf8"), "built-without-host-authority\n");
  if (name === "pi-build-remote-override") assert.match(result.stderr, /ignoring.*builders/i);
}
const noChroot = build("pi-build-no-chroot", ["--arg", "noChroot", "true"]);
assert.notEqual(noChroot.status, 0);
assert.match(noChroot.stderr, /noChroot|sandbox/i);

const direct = run("nix", ["store", "info", "--json", "--store", "unix:///nix/var/nix/daemon-socket/socket"]);
assert.equal(direct.status, 0, direct.stderr);
assert.equal(JSON.parse(direct.stdout).trusted, false);

function denied(command, args) {
  const result = spawnSync(command, args, { env, encoding: "utf8", timeout: 10000 });
  if (result.error) {
    assert.ok(["EACCES", "EPERM"].includes(result.error.code), result.error.message);
    return;
  }
  assert.equal(result.signal, null);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr + result.stdout, /root|permission|denied|not permitted|no new privileges/i);
}
denied("/run/wrappers/bin/sudo", ["-n", "true"]);
denied("/run/current-system/bin/switch-to-configuration", ["test"]);
denied("nix-env", ["--profile", "/nix/var/nix/profiles/system", "--set", "/run/current-system"]);
console.log(JSON.stringify({
  trusted: false, builds: 3, sandboxOverride: "ineffective", noChroot: "denied",
  normalDaemon: "untrusted", privilegeElevation: "denied", systemProfile: "denied", activation: "denied",
}));
