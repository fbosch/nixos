import * as Effect from "effect/Effect";
import assert from "node:assert/strict";
import { chmodSync, lstatSync, mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { devenvRuntime, serviceSocketArguments } from "../scripts/ipc/services.mts";

const roots = [];
function fixture(mode = 0o755) {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-devenv-runtime-")));
  roots.push(root);
  const project = join(root, "project");
  const environment = { XDG_RUNTIME_DIR: join(root, "runtime") };
  mkdirSync(project);
  writeFileSync(join(project, "devenv.nix"), "{}");
  mkdirSync(environment.XDG_RUNTIME_DIR, { mode: 0o700 });
  const runtime = devenvRuntime(project, root, environment);
  mkdirSync(runtime);
  chmodSync(runtime, mode);
  return { root, project, environment, runtime };
}
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
const values = (args, flag) => args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);

test("legacy user-owned Devenv runtimes become private before receiving project service grants", () => {
  for (const mode of [0o750, 0o755, 0o775, 0o777]) {
    const f = fixture(mode);
    const args = Effect.runSync(serviceSocketArguments(f.project, f.root, f.environment, true));
    assert.equal(lstatSync(f.runtime).mode & 0o777, 0o700);
    assert.equal(lstatSync(join(f.runtime, "processes")).mode & 0o777, 0o700);
    assert.deepEqual(values(args, "--allow"), [f.runtime]);
    assert.deepEqual(values(args, "--allow-unix-socket-dir-bind").sort(), [f.runtime, join(f.runtime, "processes")].sort());
  }
});

test("private Devenv runtimes retain their permissions", () => {
  const f = fixture(0o700);
  assert.ok(values(Effect.runSync(serviceSocketArguments(f.project, f.root, f.environment, true)), "--allow").includes(f.runtime));
  assert.equal(lstatSync(f.runtime).mode & 0o777, 0o700);
});

test("runtime symlinks are rejected without changing their targets' permissions", () => {
  const f = fixture();
  const target = join(f.root, "unrelated");
  mkdirSync(target);
  chmodSync(target, 0o755);
  rmSync(f.runtime, { recursive: true });
  symlinkSync(target, f.runtime);
  assert.throws(() => Effect.runSync(serviceSocketArguments(f.project, f.root, f.environment, true)), /Devenv runtime/);
  assert.equal(lstatSync(target).mode & 0o777, 0o755);
});

test("runtimes owned by another user are rejected without changing permissions", t => {
  const f = fixture();
  const uid = process.getuid();
  t.mock.method(process, "getuid", () => uid + 1);
  assert.throws(() => Effect.runSync(serviceSocketArguments(f.project, f.root, f.environment, true)), /Devenv runtime/);
  assert.equal(lstatSync(f.runtime).mode & 0o777, 0o755);
});
