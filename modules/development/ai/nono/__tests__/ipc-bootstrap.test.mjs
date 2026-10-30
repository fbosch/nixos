import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { defaultCapabilities } from "../scripts/ipc-policy.mjs";

const roots = [];
afterEach(() => { for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true }); });
function fixture() {
  const root = realpathSync(mkdtempSync("/tmp/pi-ipc-boot-")); roots.push(root);
  const home = join(root, "home"); const cwd = join(root, "work"); const agent = join(home, ".pi", "agent");
  mkdirSync(agent, { recursive: true }); mkdirSync(join(cwd, ".git"), { recursive: true });
  const profile = join(root, "profile.json"); const manifest = join(root, "manifest.json");
  writeFileSync(profile, JSON.stringify({ linux: { af_unix_mediation: "pathname" } }));
  const nono = join(root, "nono"); const raw = join(root, "pi"); const direnv = join(root, "direnv"); const marker = join(root, "executed");
  writeFileSync(nono, `#!${process.execPath}\nimport { writeFileSync } from "node:fs"; writeFileSync(${JSON.stringify(marker)}, "executed"); console.log(JSON.stringify(process.argv.slice(2)));\n`, { mode: 0o700 });
  writeFileSync(raw, "fixture");
  const run = () => spawnSync(process.execPath, [fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url)), nono, raw, profile, direnv, process.env.ENV_TEST_BINARY ?? "/usr/bin/env"], {
    cwd, env: { PATH: process.env.PATH, HOME: home, PI_CODING_AGENT_DIR: agent, PI_IPC_MANIFEST: manifest }, encoding: "utf8", timeout: 10000,
  });
  return { root, cwd, manifest, direnv, marker, run };
}

test("project environment cannot replace the captured registry or restore disabled grants", () => {
  const f = fixture();
  const disabled = structuredClone(defaultCapabilities); delete disabled.profiles.restricted["git-fsmonitor"];
  writeFileSync(f.manifest, JSON.stringify(disabled));
  const replacement = join(f.root, "replacement.json"); writeFileSync(replacement, JSON.stringify(defaultCapabilities));
  writeFileSync(join(f.cwd, ".envrc"), "fixture");
  writeFileSync(f.direnv, `#!${process.execPath}\nconsole.log(JSON.stringify({ PI_IPC_MANIFEST: ${JSON.stringify(replacement)} }));\n`, { mode: 0o700 });
  const result = f.run();
  assert.ifError(result.error); assert.equal(result.status, 0, result.stderr);
  assert.ok(existsSync(f.marker));
  assert.ok(!JSON.parse(result.stdout).includes(join(f.cwd, ".git", "fsmonitor--daemon.ipc")));
});

test("malformed inherited policy aborts startup before running Pi or nono", () => {
  const f = fixture(); writeFileSync(f.manifest, "{");
  const result = f.run();
  assert.ifError(result.error); assert.equal(result.status, 1);
  assert.match(result.stderr, /Cannot read IPC capability manifest/);
  assert.equal(existsSync(f.marker), false);
});
