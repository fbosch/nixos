import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

const packageRoot = process.env.PI_TEST_PACKAGE;
assert.ok(packageRoot, "PI_TEST_PACKAGE must point to the installed Pi package");
const require = createRequire(join(packageRoot, "package.json"));
const { probe } = require("proper-lockfile/lib/mtime-precision");
const lockfile = require("proper-lockfile");

function filesystem(milliseconds) {
  const calls = { stat: 0, utimes: 0 };
  const fs = Object.freeze({
    stat(_file, callback) {
      calls.stat++;
      callback(null, { mtime: new Date(milliseconds) });
    },
    utimes(_file, _atime, _mtime, callback) {
      calls.utimes++;
      callback(null);
    },
  });
  return { fs, calls };
}

function precision(fs) {
  return new Promise((resolve, reject) => {
    probe("lock", fs, (error, mtime, value) => {
      if (error) reject(error);
      else resolve({ mtime, precision: value });
    });
  });
}

test("precision probing supports immutable filesystem adapters and caches per adapter", async () => {
  const seconds = filesystem(1000);
  const milliseconds = filesystem(1005);

  assert.deepEqual(await precision(seconds.fs), { mtime: new Date(1000), precision: "s" });
  assert.deepEqual(await precision(milliseconds.fs), { mtime: new Date(1005), precision: "ms" });
  assert.deepEqual(await precision(seconds.fs), { mtime: new Date(1000), precision: "s" });
  assert.deepEqual(await precision(milliseconds.fs), { mtime: new Date(1005), precision: "ms" });
  assert.deepEqual(seconds.calls, { stat: 2, utimes: 1 });
  assert.deepEqual(milliseconds.calls, { stat: 2, utimes: 1 });
});

test("Pi's packaged lockfile dependency excludes competing writers and releases locks", async () => {
  const directory = await mkdtemp(join(tmpdir(), "pi-lockfile-test-"));
  const file = join(directory, "settings.json");
  try {
    await writeFile(file, "{}\n");
    const release = await lockfile.lock(file, { retries: 0 });
    try {
      await assert.rejects(lockfile.lock(file, { retries: 0 }), { code: "ELOCKED" });
    } finally {
      await release();
    }
    const releaseAgain = await lockfile.lock(file, { retries: 0 });
    await releaseAgain();
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("sandbox locks stay in runtime storage while config directories remain untouched", async () => {
  const directory = await mkdtemp(join(tmpdir(), "pi-runtime-locks-"));
  const runtime = join(directory, "locks");
  const file = join(directory, "settings.json");
  try {
    await mkdir(runtime);
    await writeFile(file, "{}");
    const script = `
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const { createRequire } = require("node:module");
      const load = createRequire(process.argv[1] + "/package.json");
      const lockfile = load("proper-lockfile");
      const file = process.argv[2];
      const runtime = process.env.PI_LOCKFILE_DIR;
      const release = lockfile.lockSync(file);
      assert.equal(fs.existsSync(file + ".lock"), false);
      assert.equal(fs.readdirSync(runtime).length, 1);
      assert.throws(() => lockfile.lockSync(file), {code:"ELOCKED"});
      release();
      assert.deepEqual(fs.readdirSync(runtime), []);
      const custom = runtime + "/custom.lock";
      const unlock = lockfile.lockSync(file, {lockfilePath:custom});
      assert.equal(fs.existsSync(custom), false);
      assert.equal(fs.readdirSync(runtime).length, 1);
      assert.throws(() => lockfile.lockSync(file, {lockfilePath:custom}), {code:"ELOCKED"});
      unlock();
    `;
    const child = spawnSync(process.execPath, ["-e", script, packageRoot, file], {
      env: { ...process.env, PI_LOCKFILE_DIR: runtime }, encoding: "utf8", timeout: 10000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
  } finally {
    await rm(directory, {recursive:true,force:true});
  }
});
