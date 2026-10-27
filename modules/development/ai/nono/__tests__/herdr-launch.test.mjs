import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

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
  const cwd = join(root, "cwd");
  const runtime = join(root, "runtime");
  const temporary = join(root, "tmp");
  for (const path of [cwd, runtime, temporary]) mkdirSync(path);
  const agent = join(home, ".pi", "agent");
  mkdirSync(agent, { recursive: true });
  const nono = join(root, "nono");
  const rawPi = join(root, "raw-pi");
  for (const [path, kind] of [[nono, "nono"], [rawPi, "pi"]]) {
    writeFileSync(path, `#!${process.execPath}
import { readFileSync } from "node:fs";
const parentName = process.platform === "linux" ? readFileSync("/proc/" + process.ppid + "/comm", "utf8").trim() : null;
console.log(JSON.stringify({kind:${JSON.stringify(kind)},parentName,clipboard:process.env.PI_CLIPBOARD_OSC52 ?? null,hint:process.env.HERDR_AGENT ?? null,pane:process.env.HERDR_PANE_ID ?? null,socket:process.env.HERDR_SOCKET_PATH ?? null,args:process.argv.slice(2)}));
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
    XDG_RUNTIME_DIR: runtime,
    TMPDIR: temporary,
  };
  for (const name of ["PI_CLIPBOARD_OSC52", "HERDR_ENV", "HERDR_AGENT", "HERDR_PANE_ID", "HERDR_SOCKET_PATH", "NODE_OPTIONS", "NODE_PATH", "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"]) delete env[name];
  Object.assign(env, environment);
  const child = spawnSync(process.execPath, [launcher, nono, rawPi, profile, "/missing-direnv", envBinary, ...args], {
    cwd,
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

test("sandboxed Herdr enables OSC 52 only in the Linux Pi child", () => {
  for (const environment of [{ HERDR_ENV: "1" }, { HERDR_ENV: "1", PI_CLIPBOARD_OSC52: "0" }]) {
    const actual = launch(environment);
    const boundary = actual.args.indexOf("--");
    assert.ok(boundary >= 0);
    assert.equal(actual.clipboard, environment.PI_CLIPBOARD_OSC52 ?? null);
    assert.ok(!actual.args.slice(0, boundary).includes("PI_CLIPBOARD_OSC52=1"));
    assert.equal(actual.args.slice(boundary + 1).includes("PI_CLIPBOARD_OSC52=1"), process.platform === "linux");
  }
  for (const environment of [{}, { HERDR_ENV: "0" }]) {
    const actual = launch(environment);
    assert.ok(!actual.args.includes("PI_CLIPBOARD_OSC52=1"));
  }
});

test("Herdr copy falls back to OSC 52 when the installed Pi runtime cannot use native clipboard helpers", {
  skip: process.platform !== "linux" || !process.env.PI_TEST_PACKAGE,
}, () => {
  const actual = launch({ HERDR_ENV: "1" });
  const root = roots.at(-1);
  const helpers = join(root, "cwd", "clipboard-helpers");
  const attempts = join(root, "cwd", "clipboard-attempts");
  mkdirSync(helpers);
  for (const name of ["wl-copy", "wl-paste", "xclip", "xsel"]) {
    writeFileSync(join(helpers, name), `#!${process.execPath}
const fs = require("node:fs");
process.stdin.resume();
process.stdin.on("end", () => {
  fs.appendFileSync(${JSON.stringify(attempts)}, ${JSON.stringify(name + "\n")});
  process.exit(1);
});
`, { mode: 0o700 });
  }
  const clipboard = pathToFileURL(join(process.env.PI_TEST_PACKAGE, "dist/utils/clipboard.js")).href;
  const probe = `
    import { copyToClipboard } from ${JSON.stringify(clipboard)};
    try { await copyToClipboard(process.argv[1]); }
    catch (error) { console.error(error.message); process.exitCode = 9; }
  `;
  const input = "første æøå\nanden";
  const probeArgs = ["--input-type=module", "-e", probe, "--"];
  const options = {
    env: { PATH: helpers, HOME: join(root, "home"), WAYLAND_DISPLAY: "fixture-wayland", HERDR_ENV: "1", PI_CLIPBOARD_OSC52: "0" },
    encoding: "utf8", timeout: 15000,
  };
  const control = spawnSync(process.execPath, [...probeArgs, input], options);
  assert.ifError(control.error);
  assert.equal(control.status, 9, control.stderr);
  assert.match(control.stderr, /Clipboard unavailable: install `wl-clipboard`/);
  assert.equal(control.stdout, "");

  const handoff = actual.args.slice(actual.args.indexOf("--") + 1);
  const copy = (text) => spawnSync(handoff[0], [...handoff.slice(1, -1), process.execPath, ...probeArgs, text], options);
  const copied = copy(input);
  assert.ifError(copied.error);
  assert.equal(copied.status, 0, copied.stderr);
  assert.equal(copied.stdout, "\x1b]52;c;" + Buffer.from(input).toString("base64") + "\x07");
  if (process.env.PI_TEST_NONO) {
    const offline = JSON.parse(readFileSync(profile, "utf8"));
    offline.network = { block: true };
    offline.credential_capture = {};
    const offlinePath = join(root, "offline.json");
    writeFileSync(offlinePath, JSON.stringify(offline));
    const boundary = actual.args.indexOf("--");
    const confinedArgs = actual.args.slice(0, boundary);
    confinedArgs[confinedArgs.indexOf("--profile") + 1] = offlinePath;
    const confined = spawnSync(process.env.PI_TEST_NONO, [
      ...confinedArgs, "--no-audit", "--no-rollback", "--",
      ...handoff.slice(0, -1), process.execPath, ...probeArgs, input,
    ], { ...options, cwd: join(root, "cwd") });
    assert.ifError(confined.error);
    assert.equal(confined.status, 0, confined.stderr);
    assert.equal(confined.stdout, copied.stdout);
  }
  const oversized = copy("x".repeat(75001));
  assert.ifError(oversized.error);
  assert.equal(oversized.status, 9, oversized.stderr);
  assert.match(oversized.stderr, /OSC 52 size limit/);
  assert.equal(oversized.stdout, "");
  assert.deepEqual(readFileSync(attempts, "utf8").trim().split("\n"), Array(process.env.PI_TEST_NONO ? 4 : 3).fill("wl-copy"));
});

test("direct launches retain their explicit clipboard policy", () => {
  for (const clipboard of [undefined, "0", "1"]) {
    const actual = launch({ HERDR_ENV: "1", ...(clipboard === undefined ? {} : { PI_CLIPBOARD_OSC52: clipboard }) }, ["--no-sandbox", "--version"]);
    assert.equal(actual.kind, "pi");
    assert.equal(actual.clipboard, clipboard ?? null);
  }
});
