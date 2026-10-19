import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, utimesSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { loadProjectEnvironment } from "../scripts/launcher.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

const roots = [];
const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));

function fixture(withEnvrc = true) {
  const root = mkdtempSync(join(tmpdir(), "pi-direnv-bootstrap-"));
  roots.push(root);
  const cwd = join(root, "Program Files (x86)");
  mkdirSync(cwd);
  if (withEnvrc) writeFileSync(join(cwd, ".envrc"), "export SAMPLE=loaded\n");
  const direnv = join(root, "direnv");
  writeFileSync(direnv, "fixture");
  return { root, cwd, direnv };
}
afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

test("missing launch-directory .envrc skips direnv, including an ancestor .envrc", () => {
  const { root, cwd } = fixture(false);
  writeFileSync(join(root, ".envrc"), "exit 1\n");
  const base = { SAMPLE: "inherited" };
  const loaded = loadProjectEnvironment(cwd, base, "/missing-direnv", () => assert.fail("direnv must not run"));
  assert.deepEqual(loaded, base);
  assert.notEqual(loaded, base);
});

test("loads exports and removals using the pinned binary and exact cwd without shell preloads", () => {
  const { cwd, direnv } = fixture();
  const base = { SAMPLE: "old", REMOVE: "old", BASH_ENV: "/unsafe", ENV: "/unsafe", NODE_OPTIONS: "--require /unsafe", NODE_PATH: "/unsafe" };
  const loaded = loadProjectEnvironment(cwd, base, direnv, (binary, args, options) => {
    assert.equal(binary, direnv);
    assert.deepEqual(args, ["export", "json"]);
    assert.equal(options.cwd, cwd);
    assert.equal(options.timeout, 120_000);
    for (const name of ["BASH_ENV", "ENV", "NODE_OPTIONS", "NODE_PATH"]) assert.equal(options.env[name], undefined);
    return { status: 0, stderr: "direnv: loading .envrc\n", stdout: JSON.stringify({ SAMPLE: "loaded", REMOVE: null, NODE_OPTIONS: "--require /unsafe", NODE_PATH: "/unsafe" }) };
  });
  assert.equal(loaded.SAMPLE, "loaded");
  assert.equal(loaded.REMOVE, undefined);
  assert.equal(loaded.NODE_OPTIONS, undefined);
  assert.equal(loaded.NODE_PATH, undefined);
  assert.equal(base.SAMPLE, "old");
});

test("already-loaded environment accepts an empty diff", () => {
  const { cwd, direnv } = fixture();
  assert.deepEqual(loadProjectEnvironment(cwd, { SAMPLE: "loaded" }, direnv, () => ({ status: 0, stdout: "", stderr: "" })), { SAMPLE: "loaded" });
});

for (const [name, result] of [
  ["blocked approval", { status: 1, stdout: "", stderr: "direnv: error .envrc is blocked" }],
  ["exit-zero evaluation failure", { status: 0, stdout: "{}", stderr: 'error: opening file "/": Permission denied' }],
  ["nonzero evaluation failure", { status: 1, stdout: "{}", stderr: "" }],
  ["timeout", { status: null, error: new Error("ETIMEDOUT"), stdout: "", stderr: "" }],
  ["malformed JSON", { status: 0, stdout: "not json", stderr: "" }],
  ["invalid export object", { status: 0, stdout: "[]", stderr: "" }],
  ["invalid export value", { status: 0, stdout: '{"SAMPLE":42}', stderr: "" }],
]) {
  test(`rejects ${name} without exposing exported secrets`, () => {
    const { cwd, direnv } = fixture();
    assert.throws(() => loadProjectEnvironment(cwd, {}, direnv, () => result), /direnv/);
  });
}

test("existing .envrc fails closed when the packaged direnv binary is missing", () => {
  const { cwd } = fixture();
  assert.throws(() => loadProjectEnvironment(cwd, {}, "/missing-direnv"), /executable missing/);
});

test("a directory named .envrc fails closed", () => {
  const { cwd, direnv } = fixture(false);
  mkdirSync(join(cwd, ".envrc"));
  assert.throws(() => loadProjectEnvironment(cwd, {}, direnv), /must be a file/);
});

for (const blocked of [false, true]) {
  test(`launcher ${blocked ? "does not start nono after a blocked load" : "passes loaded environment and arguments into nono"}`, () => {
    const { root, cwd, direnv } = fixture();
    const home = join(root, "home");
    const observed = join(root, "observed.json");
    mkdirSync(home);
    writeFileSync(direnv, `#!${process.execPath}\n${blocked
      ? 'console.error("direnv: error .envrc is blocked"); process.exit(1);'
      : 'console.log(JSON.stringify({SAMPLE:"loaded", REMOVE:null, PATH:"/project/bin"}));'}\n`, { mode: 0o700 });
    chmodSync(direnv, 0o700);
    const nono = join(root, "nono");
    writeFileSync(nono, `#!${process.execPath}\nimport {writeFileSync} from "node:fs";writeFileSync(${JSON.stringify(observed)},JSON.stringify({path:process.env.PATH,sample:process.env.SAMPLE,removed:process.env.REMOVE,args:process.argv.slice(2)}));\n`, { mode: 0o700 });
    const env = { ...process.env, HOME: home, XDG_CONFIG_HOME: join(home, ".config"), XDG_CACHE_HOME: join(home, ".cache"), XDG_DATA_HOME: join(home, ".local", "share"), SAMPLE: "old", REMOVE: "old", PI_CODING_AGENT_DIR: join(home, ".pi", "agent"), XDG_STATE_HOME: join(home, ".local", "state") };
    delete env.NODE_OPTIONS;
    delete env.NODE_PATH;
    for (const name of ["GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]) delete env[name];
    const result = spawnSync(process.execPath, [launcher, nono, process.execPath, profile, direnv, envBinary, "--print", "hello"], { cwd, env, encoding: "utf8" });
    if (blocked) {
      assert.equal(result.status, 1, result.stderr);
      assert.equal(existsSync(observed), false);
      assert.match(result.stderr, /direnv environment load failed/);
    } else {
      assert.equal(result.status, 0, result.stderr);
      const actual = JSON.parse(readFileSync(observed, "utf8"));
      assert.equal(actual.sample, "loaded");
      assert.equal(actual.path.split(":")[0], env.PATH.split(":")[0]);
      assert.ok(actual.path.split(":").includes("/project/bin"));
      assert.equal(actual.removed, undefined);
      assert.deepEqual(actual.args.slice(-2), ["--print", "hello"]);
      assert.ok(actual.args.includes("--allow-cwd"));
    }
  });
}

test("real direnv loads an approved fixture and rejects changed content without reapproval", {
  skip: !process.env.PI_TEST_DIRENV,
}, () => {
  const { root, cwd } = fixture();
  const home = join(root, "isolated-home");
  const config = join(home, ".config", "direnv");
  mkdirSync(config, { recursive: true });
  const env = {
    ...process.env,
    HOME: home,
    DIRENV_CONFIG: config,
    XDG_CONFIG_HOME: join(home, ".config"),
    XDG_DATA_HOME: join(home, ".local", "share"),
    XDG_CACHE_HOME: join(home, ".cache"),
    REMOVE: "old",
  };
  for (const name of ["DIRENV_DIFF", "DIRENV_DIR", "DIRENV_FILE", "DIRENV_WATCHES", "BASH_ENV", "ENV", "NODE_OPTIONS", "NODE_PATH"]) delete env[name];
  writeFileSync(join(cwd, ".envrc"), "export SAMPLE=loaded\nunset REMOVE\n");
  // Only this synthetic file is approved, in a disposable trust store.
  const approval = spawnSync(process.env.PI_TEST_DIRENV, ["allow", "."], { cwd, env, encoding: "utf8" });
  assert.equal(approval.status, 0, approval.stderr);
  const loaded = loadProjectEnvironment(cwd, env, process.env.PI_TEST_DIRENV);
  assert.equal(loaded.SAMPLE, "loaded");
  assert.equal(loaded.REMOVE, undefined);
  writeFileSync(join(cwd, ".envrc"), "export SAMPLE=changed\n");
  // Direnv watches second-resolution mtimes; advance the fixture without sleeping.
  const changedAt = new Date(Date.now() + 2_000);
  utimesSync(join(cwd, ".envrc"), changedAt, changedAt);
  assert.throws(() => loadProjectEnvironment(cwd, loaded, process.env.PI_TEST_DIRENV), /environment load failed/);
});
