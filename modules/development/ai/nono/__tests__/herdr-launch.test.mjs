import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const roots = [];

afterEach(() => {
  for (const root of roots.splice(0)) rmSync(root, { recursive: true, force: true });
});

function launch(environment, args = []) {
  const root = mkdtempSync(join(tmpdir(), "pi-herdr-launch-"));
  roots.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  mkdirSync(agent, { recursive: true });
  const nono = join(root, "nono");
  const rawPi = join(root, "raw-pi");
  for (const [path, kind] of [[nono, "nono"], [rawPi, "pi"]]) {
    writeFileSync(path, `#!${process.execPath}
import { readFileSync } from "node:fs";
const parentName = process.platform === "linux" ? readFileSync("/proc/" + process.ppid + "/comm", "utf8").trim() : null;
console.log(JSON.stringify({kind:${JSON.stringify(kind)},parentName,hint:process.env.HERDR_AGENT ?? null,pane:process.env.HERDR_PANE_ID ?? null,socket:process.env.HERDR_SOCKET_PATH ?? null,args:process.argv.slice(2)}));
`, { mode: 0o700 });
  }
  const env = {
    ...process.env,
    HOME: home,
    PI_CODING_AGENT_DIR: agent,
    XDG_CONFIG_HOME: join(home, ".config"),
    XDG_CACHE_HOME: join(home, ".cache"),
    XDG_DATA_HOME: join(home, ".local", "share"),
    XDG_STATE_HOME: join(home, ".local", "state"),
    XDG_RUNTIME_DIR: root,
    TMPDIR: root,
  };
  for (const name of ["HERDR_ENV", "HERDR_AGENT", "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "NODE_OPTIONS", "NODE_PATH"]) delete env[name];
  Object.assign(env, environment);
  const child = spawnSync(process.execPath, [launcher, nono, rawPi, profile, "/missing-direnv", ...args], {
    cwd: root,
    env,
    encoding: "utf8",
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  return JSON.parse(child.stdout);
}

for (const args of [[], ["--no-sandbox", "--version"]]) {
  test(`host-visible bootstrap identifies as pi for ${args.length === 0 ? "sandboxed" : "direct"} launches`, { skip: process.platform !== "linux" }, () => {
    const actual = launch({ HERDR_ENV: "1" }, args);
    assert.equal(actual.parentName, "pi");
  });
}

for (const hint of [undefined, "", "claude"]) {
  test(`Herdr launch passes a pi hint to the nono wrapper with ${hint === undefined ? "no" : JSON.stringify(hint)} inherited hint`, () => {
    const environment = {
      HERDR_ENV: "1",
      HERDR_PANE_ID: "wFixture:p1",
      HERDR_SOCKET_PATH: "/fixture/herdr.sock",
      ...(hint === undefined ? {} : { HERDR_AGENT: hint }),
    };
    const args = ["--print", "a prompt with spaces"];
    const actual = launch(environment, args);
    assert.equal(actual.kind, "nono");
    assert.equal(actual.hint, "pi");
    assert.equal(actual.pane, environment.HERDR_PANE_ID);
    assert.equal(actual.socket, environment.HERDR_SOCKET_PATH);
    assert.deepEqual(actual.args.slice(-args.length), args);
  });
}

for (const environment of [{}, { HERDR_ENV: "0" }, { HERDR_AGENT: "custom" }, { HERDR_ENV: "0", HERDR_AGENT: "custom" }]) {
  test(`non-Herdr launches preserve the inherited hint: ${JSON.stringify(environment)}`, () => {
    const actual = launch(environment);
    assert.equal(actual.kind, "nono");
    assert.equal(actual.hint, environment.HERDR_AGENT ?? null);
  });
}

for (const hint of [undefined, "custom"]) {
  test(`--no-sandbox does not add a wrapper hint with ${hint === undefined ? "no" : "an"} inherited hint`, () => {
    const actual = launch({ HERDR_ENV: "1", ...(hint === undefined ? {} : { HERDR_AGENT: hint }) }, ["--no-sandbox", "--version"]);
    assert.equal(actual.kind, "pi");
    assert.equal(actual.hint, hint ?? null);
    assert.deepEqual(actual.args, ["--version"]);
  });
}
