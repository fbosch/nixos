import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const [cwd, common, sibling, gitBinary, wtBinary] = process.argv.slice(2);
function run(binary, args) {
  const child = spawnSync(binary, args, { encoding: "utf8", timeout: 10000 });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  return child.stdout.trim();
}

assert.ok(readFileSync(join(common, "HEAD"), "utf8").startsWith("ref: "));
assert.equal(run(gitBinary, ["rev-parse", "--show-toplevel"]), cwd);
assert.equal(run(gitBinary, ["status", "--porcelain"]), "");
writeFileSync(join(cwd, "note.txt"), "worktree fixture\n");
run(gitBinary, ["add", "note.txt"]);
assert.equal(run(gitBinary, ["diff", "--cached", "--name-only"]), "note.txt");
const object = run(gitBinary, ["hash-object", "-w", "note.txt"]);
run(gitBinary, ["update-ref", "refs/pi-test/blob", object]);
assert.equal(run(gitBinary, ["rev-parse", "refs/pi-test/blob"]), object);
assert.ok(run(gitBinary, ["worktree", "list", "--porcelain"]).includes(cwd));
if (wtBinary) assert.ok(run(wtBinary, ["list", "--format=json", "--no-progressive"]).includes(cwd));
for (const operation of [
  () => readdirSync(sibling),
  () => readFileSync(join(sibling, "private.txt"), "utf8"),
  () => writeFileSync(join(sibling, "private.txt"), "changed"),
]) assert.throws(operation, (error) => ["EACCES", "EPERM"].includes(error.code));
