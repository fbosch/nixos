import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [ssh, sshKeygen, sshAdd] = process.argv.slice(2);
for (const name of ["config", "known_hosts", "id_ed25519.pub"]) {
  assert.ok(readFileSync(join(ssh, name), "utf8").length > 0);
}
const denied = (operation) => assert.throws(operation, error => ["EACCES", "EPERM"].includes(error.code));
for (const name of ["id_ed25519", "unrelated"]) denied(() => readFileSync(join(ssh, name), "utf8"));
denied(() => appendFileSync(join(ssh, "known_hosts"), "changed"));
denied(() => mkdirSync(join(ssh, "new-directory")));
const lookup = spawnSync(sshKeygen, ["-F", "sandbox.example", "-f", join(ssh, "known_hosts")], { encoding: "utf8", timeout: 10000 });
assert.ifError(lookup.error);
assert.equal(lookup.status, 0, lookup.stderr);
assert.ok(lookup.stdout.includes("sandbox.example"));
const agent = spawnSync(sshAdd, ["-l"], { encoding: "utf8", timeout: 10000 });
assert.ifError(agent.error);
assert.equal(agent.status, 1, agent.stderr);
assert.match(`${agent.stdout}${agent.stderr}`, /agent has no identities/i);
