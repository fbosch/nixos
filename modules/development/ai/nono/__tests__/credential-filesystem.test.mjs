import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const base = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
const secretRoots = ["/run/secrets", "/run/secrets.d"];

function fixture(overlapping = false) {
  const root = mkdtempSync(join(tmpdir(), "pi-secret-denial-"));
  const state = mkdtempSync(join(process.cwd(), ".pi-secret-state-"));
  const work = overlapping ? root : join(root, "work");
  const generations = join(root, "secrets.d");
  const active = join(root, "secrets");
  const first = join(generations, "1", "api-key");
  const second = join(generations, "2", "api-key");
  for (const directory of [work, join(generations, "1")]) mkdirSync(directory, { recursive: true });
  writeFileSync(first, "synthetic-credential", { mode: 0o400 });
  symlinkSync(join(generations, "1"), active);
  writeFileSync(join(work, "ordinary-file"), "ordinary content");
  const profile = join(root, "profile.json");
  writeFileSync(profile, JSON.stringify({
    ...base,
    filesystem: {
      ...base.filesystem,
      deny: (base.filesystem.deny ?? []).map((path) =>
        path === "/run/secrets" ? active : path === "/run/secrets.d" ? generations : path),
    },
  }));
  return {
    root, state, work, generations, active, first, second, profile,
    environment: { ...process.env, XDG_STATE_HOME: state },
    rotate() {
      mkdirSync(join(generations, "2"));
      writeFileSync(second, "synthetic-rotated-credential", { mode: 0o400 });
      symlinkSync(join(generations, "2"), join(root, "replacement"));
      renameSync(join(root, "replacement"), active);
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
      rmSync(state, { recursive: true, force: true });
    },
  };
}

test("Pi policy denies the active SOPS tree and its stable generation root", () => {
  for (const root of secretRoots) assert.ok(base.filesystem.deny?.includes(root), `Missing secret-root denial: ${root}`);
});

test("installed Nono accepts the secret-denying Pi profile", {
  skip: !process.env.NONO_PROFILE_TEST_BINARY,
}, () => {
  const child = spawnSync(process.env.NONO_PROFILE_TEST_BINARY, [
    "profile", "validate", fileURLToPath(new URL("../scripts/profile.json", import.meta.url)),
  ], { encoding: "utf8" });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr || child.stdout);
});

test("macOS denies secret aliases and old/new SOPS generations while ordinary reads work", {
  skip: process.platform !== "darwin" || !process.env.NONO_TEST_BINARY,
  timeout: 30_000,
}, async () => {
  const f = fixture();
  let child;
  let timer;
  try {
    assert.equal(readFileSync(f.first, "utf8"), "synthetic-credential");
    const command = `
      const fs = require("node:fs");
      const assert = require("node:assert/strict");
      console.log("secret-probe-ready");
      process.stdin.once("data", () => {
        for (const path of ${JSON.stringify([join(f.active, "api-key"), f.first, f.second, realpathSync(f.first)])}) {
          assert.throws(() => fs.readFileSync(path), (error) => ["EPERM", "EACCES"].includes(error.code), path);
        }
        assert.throws(() => fs.linkSync(${JSON.stringify(f.first)}, "credential-alias"),
          (error) => ["EPERM", "EACCES"].includes(error.code));
        assert.equal(fs.readFileSync("ordinary-file", "utf8"), "ordinary content");
        console.log("secret-probe-passed");
        process.stdin.destroy();
      });
    `;
    child = spawn(process.env.NONO_TEST_BINARY, [
      "run", "--profile", f.profile, "--allow-cwd", "--no-rollback", "--no-audit", "--",
      process.execPath, "-e", command,
    ], { cwd: f.work, env: f.environment, stdio: ["pipe", "pipe", "pipe"] });
    let output = "";
    let diagnostics = "";
    const exited = once(child, "exit");
    const ready = new Promise((resolve) => child.stdout.on("data", (chunk) => {
      output += chunk;
      if (output.includes("secret-probe-ready")) resolve();
    }));
    child.stderr.on("data", (chunk) => { diagnostics += chunk; });
    timer = setTimeout(() => child.kill("SIGTERM"), 20_000);
    await Promise.race([
      ready,
      exited.then(() => { throw new Error(`Secret probe exited before readiness: ${diagnostics}`); }),
    ]);
    // Rotate after confinement: denying only the current symlink target would leak generation 2.
    f.rotate();
    child.stdin.end("continue");
    const [status, signal] = await exited;
    assert.equal(signal, null, diagnostics);
    assert.equal(status, 0, diagnostics);
    assert.match(output, /secret-probe-passed/);
  } finally {
    clearTimeout(timer);
    if (child && child.exitCode === null && child.signalCode === null) {
      child.kill("SIGTERM");
      await once(child, "exit");
    }
    f.cleanup();
  }
});

test("Linux refuses a broad grant that would cover a denied SOPS root", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  const f = fixture(true);
  try {
    const child = spawnSync(process.env.NONO_TEST_BINARY, [
      "run", "--profile", f.profile, "--allow-cwd", "--no-rollback", "--no-audit", "--",
      process.execPath, "-e", 'process.stdout.write("must-not-run")',
    ], { cwd: f.work, env: f.environment, encoding: "utf8", timeout: 20_000 });
    assert.ifError(child.error);
    assert.notEqual(child.status, 0);
    assert.match(child.stderr, /Landlock deny-overlap/);
    assert.doesNotMatch(child.stdout, /must-not-run/);
  } finally {
    f.cleanup();
  }
});
