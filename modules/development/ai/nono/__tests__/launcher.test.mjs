import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { once } from "node:events";
import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { launchArguments, launchCommand, prepareJitiCache, prepareNpmCache } from "../scripts/launcher.mjs";
import { sandboxRuntimeCommand } from "../scripts/sandbox-runtime.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

test("profile keeps config access narrow and Azure CLI state writable", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  assert.ok(!profile.filesystem.read.includes("$HOME/.config"));
  assert.ok(!profile.filesystem.allow.includes("$HOME/.config"));
  assert.ok(profile.filesystem.allow.includes("$HOME/.azure"));
  assert.deepEqual(profile.filesystem.bypass_protection, ["$HOME/.azure"]);
});

test("profile grants temporary-file reads without adding temporary-directory write grants", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  for (const path of ["/tmp", "$TMPDIR"]) {
    assert.ok(profile.filesystem.read.includes(path));
    assert.ok(!profile.filesystem.allow.includes(path));
  }
});

test("profile grants npm cache and log writes without making all npm state writable", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  assert.deepEqual(profile.filesystem.allow, [
    "$HOME/.pi",
    "$HOME/.claude/projects",
    "$HOME/.npm/_cacache",
    "$HOME/.npm/_logs",
    "$HOME/.azure",
    "$HOME/.azure-devops/python-sdk/cache",
    { path: "/dev/dri", when: "linux" },
  ]);
});

test("profile grants Claude bridge session storage without exposing credentials", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  assert.ok(profile.filesystem.allow.includes("$HOME/.claude/projects"));
  for (const path of ["$HOME", "$HOME/.claude", "$HOME/.claude/.credentials.json"]) {
    assert.ok(!profile.filesystem.allow.includes(path));
    assert.ok(!profile.filesystem.read.includes(path));
  }
});

test("profile permits managed global package reads without package writes", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  const modules = "$HOME/.local/state/pnpm-globals/current/node_modules";
  assert.ok(profile.filesystem.read.includes(modules));
  for (const path of ["$HOME/.local/state", "$HOME/.local/state/pnpm-globals", modules]) {
    assert.ok(!profile.filesystem.allow.includes(path));
  }
});

test("Linux launches managed global package shims while protecting packages and neighboring state", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  // /tmp is already granted by the default profile, so isolate HOME outside it.
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-global-package-test-")));
  created.push(root);
  const home = join(root, "home");
  const cwd = join(root, "project");
  const state = join(home, ".local", "state", "pnpm-globals");
  const modules = join(state, "current", "node_modules");
  const bin = join(modules, ".bin");
  const dependency = join(modules, ".pnpm", "fallow-fixture", "node_modules", "fallow");
  mkdirSync(bin, { recursive: true });
  mkdirSync(dependency, { recursive: true });
  mkdirSync(cwd);
  const program = join(dependency, "lsp.cjs");
  writeFileSync(program, 'console.log("fallow-lsp fixture");\n');
  symlinkSync(dependency, join(modules, "fallow"));
  const shim = join(bin, "fallow-lsp");
  writeFileSync(shim, `#!${process.execPath}\nrequire("../fallow/lsp.cjs");\n`, { mode: 0o755 });
  const neighbor = join(state, "input-fingerprint");
  writeFileSync(neighbor, "private state");
  // Only filesystem confinement is under test; keep nested runs offline.
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  profile.network = { block: true };
  profile.credential_capture = {};
  const offlineProfile = join(root, "profile.json");
  writeFileSync(offlineProfile, JSON.stringify(profile));
  const child = spawnSync(process.env.NONO_TEST_BINARY, [
    "run", "--profile", offlineProfile, "--allow-cwd", "--no-audit", "--no-rollback", "--block-net", "--",
    process.execPath, "-e", `
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const { spawnSync } = require("node:child_process");
      const [shim, program, neighbor] = process.argv.slice(1);
      const child = spawnSync(shim, [], { encoding: "utf8" });
      assert.ifError(child.error);
      assert.equal(child.status, 0, child.stderr);
      assert.equal(child.stdout.trim(), "fallow-lsp fixture");
      assert.throws(() => fs.writeFileSync(program, "changed"), { code: "EACCES" });
      assert.throws(() => fs.readFileSync(neighbor), { code: "EACCES" });
    `, shim, program, neighbor,
  ], { cwd, env: { ...process.env, HOME: home, XDG_STATE_HOME: join(home, ".local", "state") }, encoding: "utf8", timeout: 30000 });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
});

const created = [];
function fixture() {
  const root = mkdtempSync(join(tmpdir(), "pi-launch-test-"));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const cwd = join(root, "project");
  mkdirSync(agent, { recursive: true });
  mkdirSync(cwd);
  const nono = join(root, "nono");
  const raw = join(root, "raw-pi");
  const profile = join(root, "pi.json");
  for (const path of [nono, raw, profile]) writeFileSync(path, path === profile ? "{}" : "fixture");
  const launch = (args = [], env = {}) => launchCommand(args, cwd, agent, home, env, nono, raw, profile, envBinary);
  return { root, home, agent, cwd, nono, raw, profile, launch };
}
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });
function values(args, flag) {
  return args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
}

test("PI_NVIM_SOCKET grants only connect access to the inherited Neovim socket", async () => {
  const { root, cwd, agent, home, raw, profile } = fixture();
  const socket = join(root, "nvim.sock");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try {
    for (const platform of ["darwin", "linux"]) {
      const args = launchArguments(cwd, agent, home, { PI_NVIM_SOCKET: socket }, profile, raw, envBinary, platform);
      assert.deepEqual(values(args, "--allow-unix-socket"), [socket]);
      for (const flag of ["--allow-unix-socket-bind", "--allow-unix-socket-dir", "--allow-unix-socket-dir-bind", "--allow-unix-socket-subtree", "--allow-unix-socket-subtree-bind", "--bypass-protection"]) {
        assert.deepEqual(values(args, flag), [], flag);
      }
      assert.ok(!values(args, "--allow").includes(root));
      assert.ok(!values(args, "--read").includes(root));
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test("launches without PI_NVIM_SOCKET do not grant editor socket access", () => {
  const { launch } = fixture();
  for (const value of [undefined, ""]) {
    assert.deepEqual(values(launch([], { PI_NVIM_SOCKET: value }), "--allow-unix-socket"), []);
  }
});

test("missing PI_NVIM_SOCKET paths warn and leave editor socket access disabled", t => {
  const { root, launch } = fixture();
  const expected = launch();
  const warning = t.mock.method(console, "warn", () => {});
  const missing = join(root, "missing.sock");
  const dangling = join(root, "dangling.sock");
  symlinkSync(missing, dangling);
  const sockets = [missing, join(root, "missing-editor", "nvim.sock"), dangling];
  for (const socket of sockets) assert.deepEqual(launch([], { PI_NVIM_SOCKET: socket }), expected);
  assert.equal(warning.mock.callCount(), sockets.length);
  for (const [index, call] of warning.mock.calls.entries()) {
    assert.match(call.arguments[0], /PI_NVIM_SOCKET.*missing.*continuing without Neovim access/);
    assert.ok(call.arguments[0].includes(JSON.stringify(sockets[index])));
  }
});

test("invalid PI_NVIM_SOCKET paths fail closed before entering the sandbox", () => {
  const { root, launch } = fixture();
  const file = join(root, "not-a-socket");
  writeFileSync(file, "fixture");
  for (const [path, message] of [
    ["relative.sock", /PI_NVIM_SOCKET.*absolute/],
    [file, /PI_NVIM_SOCKET.*socket/],
    [root, /PI_NVIM_SOCKET.*socket/],
  ]) {
    assert.throws(() => launch([], { PI_NVIM_SOCKET: path }), message);
  }
});

test("prepares missing npm cache and log directories without replacing existing contents", () => {
  const { home } = fixture();
  prepareNpmCache(home);
  const cached = join(home, ".npm", "_cacache", "package");
  assert.ok(existsSync(join(home, ".npm", "_logs")));
  writeFileSync(cached, "cached");
  prepareNpmCache(home);
  assert.equal(readFileSync(cached, "utf8"), "cached");
});

test("Linux prepares a missing Jiti cache before sandboxing and preserves an existing cache", () => {
  const { root } = fixture();
  const temporary = join(root, "temporary");
  const cache = join(temporary, "jiti");
  prepareJitiCache(temporary, "linux");
  assert.ok(existsSync(cache));
  const cached = join(cache, "extension.mjs");
  writeFileSync(cached, "cached");
  prepareJitiCache(temporary, "linux");
  assert.equal(readFileSync(cached, "utf8"), "cached");
});

test("Jiti cache preparation does not change Darwin runtime directories", () => {
  const { root } = fixture();
  const temporary = join(root, "temporary");
  prepareJitiCache(temporary, "darwin");
  assert.equal(existsSync(temporary), false);
});

test("Linux profile permits Jiti cache write/read cycles and clipboard/image temporary-file reads", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  const { root, cwd, home } = fixture();
  const temporary = join(root, "temporary");
  prepareJitiCache(temporary, "linux");
  const cache = join(temporary, "jiti", "extension.mjs");
  const clipboard = join(temporary, "clipboard.txt");
  const image = join(temporary, "picture.png");
  writeFileSync(clipboard, "clipboard fixture");
  writeFileSync(image, Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  const child = spawnSync(process.env.NONO_TEST_BINARY, [
    "run", "--profile", new URL("../scripts/profile.json", import.meta.url).pathname, "--allow-cwd", "--",
    process.execPath, "-e", `
      const fs = require("node:fs");
      const assert = require("node:assert/strict");
      fs.writeFileSync(process.argv[1], "compiled extension");
      assert.equal(fs.readFileSync(process.argv[1], "utf8"), "compiled extension");
      assert.equal(fs.readFileSync(process.argv[2], "utf8"), "clipboard fixture");
      assert.deepEqual([...fs.readFileSync(process.argv[3])], [0x89, 0x50, 0x4e, 0x47]);
    `, cache, clipboard, image,
  ], { cwd, env: { ...process.env, HOME: home, XDG_STATE_HOME: join(root, "state"), TMPDIR: temporary }, encoding: "utf8" });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
});

test("Linux profile permits npm cache and log writes but denies other npm state writes", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  // The default profile permits /tmp writes; place the denied-write fixture outside /tmp.
  const root = mkdtempSync(join(homedir(), "pi-npm-profile-test-"));
  created.push(root);
  const home = join(root, "home");
  const cwd = join(root, "project");
  const cache = join(home, ".npm", "_cacache");
  const logs = join(home, ".npm", "_logs");
  prepareNpmCache(home);
  mkdirSync(cwd);
  const outside = join(home, ".npm", "unrelated");
  writeFileSync(outside, "unchanged");
  const child = spawnSync(process.env.NONO_TEST_BINARY, [
    "run", "--profile", new URL("../scripts/profile.json", import.meta.url).pathname, "--allow-cwd", "--",
    process.execPath, "-e", `
      const fs = require("node:fs");
      const path = require("node:path");
      const assert = require("node:assert/strict");
      const temporary = path.join(process.argv[1], "tmp");
      fs.mkdirSync(temporary);
      const cached = path.join(temporary, "package");
      fs.writeFileSync(cached, "cache fixture");
      assert.equal(fs.readFileSync(cached, "utf8"), "cache fixture");
      const log = path.join(process.argv[2], "npm.log");
      fs.writeFileSync(log, "log fixture");
      assert.equal(fs.readFileSync(log, "utf8"), "log fixture");
      assert.throws(() => fs.writeFileSync(process.argv[3], "changed"), { code: "EACCES" });
    `, cache, logs, outside,
  ], { cwd, env: { ...process.env, HOME: home }, encoding: "utf8" });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.equal(readFileSync(outside, "utf8"), "unchanged");
});

test("always selects absolute nono, immutable profile and distinct raw Pi, preserving argv", () => {
  const { launch, nono, raw, profile, home } = fixture();
  const args = ["--print", "a prompt with spaces", "--", "--no-sandbox"];
  const command = launch(args, { NONO_CAP_FILE: "/forged/capability.json" });
  assert.equal(command[0], nono);
  assert.deepEqual(command.slice(1, 4), ["run", "--profile", profile]);
  assert.deepEqual(command.slice(command.indexOf("--") + 1), [
    envBinary, "--",
    `GH_CONFIG_DIR=${join(home, ".cache", "pi", "gh")}`,
    `npm_config_cache=${join(home, ".cache", "pi", "npm")}`,
    `UV_CACHE_DIR=${join(home, ".cache", "pi", "uv")}`,
    `UV_PYTHON_INSTALL_DIR=${join(home, ".cache", "pi", "uv-python")}`,
    `UV_TOOL_DIR=${join(home, ".cache", "pi", "uv-tools")}`,
    "NODE_OPTIONS=--disable-warning=UNDICI-EHPA", raw, ...args,
  ]);
  assert.notEqual(command[0], raw);
  assert.ok(command.includes("--allow-cwd"));
  assert.deepEqual(values(command, "--suppress-save-prompt"), ["/"]);
});
test("sandbox runtime state is prepared before grants and separated from supervisor credentials", () => {
  const { root, home, cwd, agent, nono, profile } = fixture();
  const cache = join(home, ".cache", "pi");
  const runtime = join(root, "runtime");
  mkdirSync(runtime);
  writeFileSync(nono, `#!${process.execPath}
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const { spawnSync } = require("node:child_process");
    assert.equal(process.env.GH_CONFIG_DIR, path.join(process.env.HOME, ".config", "gh"));
    const cache = path.join(process.env.HOME, ".cache", "pi");
    assert.ok(fs.statSync(cache).isDirectory());
    assert.ok(process.argv.some((part, index, args) => part === "--allow" && args[index + 1] === fs.realpathSync(cache)));
    for (const name of ["gh", "npm", "uv", "uv-python", "uv-tools"]) assert.ok(fs.statSync(path.join(cache, name)).isDirectory());
    const command = process.argv.slice(process.argv.indexOf("--") + 1);
    const child = spawnSync(command[0], command.slice(1), { stdio: "inherit", env: { ...process.env, GH_TOKEN: "synthetic-proxy-placeholder" } });
    if (child.error) throw child.error;
    process.exit(child.status ?? 1);
  `, { mode: 0o700 });
  chmodSync(nono, 0o700);
  const probe = `
    const fs = require("node:fs");
    const path = require("node:path");
    const names = ["GH_CONFIG_DIR", "npm_config_cache", "UV_CACHE_DIR", "UV_PYTHON_INSTALL_DIR", "UV_TOOL_DIR"];
    for (const name of names) fs.writeFileSync(path.join(process.env[name], "state"), "preserved");
    console.log(JSON.stringify({ ...Object.fromEntries(names.map(name => [name, process.env[name]])), token: process.env.GH_TOKEN, other: process.env.OTHER }));
  `;
  const args = [new URL("../scripts/launcher.mjs", import.meta.url).pathname, nono, process.execPath, profile, "/missing-direnv", envBinary, "-e", probe];
  const environment = {
    HOME: home, PATH: process.env.PATH, TMPDIR: runtime, XDG_RUNTIME_DIR: runtime, PI_CODING_AGENT_DIR: agent,
    GH_CONFIG_DIR: "/project/credentials", npm_config_cache: "/host/npm", UV_CACHE_DIR: "/host/uv",
    UV_PYTHON_INSTALL_DIR: "/host/python", UV_TOOL_DIR: "/host/tools", OTHER: "preserved",
  };
  const child = spawnSync(process.execPath, args, { cwd, env: environment, encoding: "utf8", timeout: 15000 });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.deepEqual(JSON.parse(child.stdout), {
    GH_CONFIG_DIR: join(cache, "gh"), npm_config_cache: join(cache, "npm"), UV_CACHE_DIR: join(cache, "uv"),
    UV_PYTHON_INSTALL_DIR: join(cache, "uv-python"), UV_TOOL_DIR: join(cache, "uv-tools"),
    token: "synthetic-proxy-placeholder", other: "preserved",
  });
  const bypass = spawnSync(process.execPath, [...args.slice(0, 6), "--no-sandbox", "-e", "console.log(process.env.UV_TOOL_DIR)"], {
    cwd, env: environment, encoding: "utf8", timeout: 15000,
  });
  assert.equal(bypass.status, 0, bypass.stderr);
  assert.equal(bypass.stdout.trim(), "/host/tools");
  assert.equal(readFileSync(join(cache, "uv-tools", "state"), "utf8"), "preserved");
});

for (const [name, access] of [
  ["SSH_AUTH_SOCK", "SSH agent access"],
  ["PI_NVIM_SOCKET", "Neovim access"],
  ["XDG_RUNTIME_DIR", "runtime-directory access"],
]) {
  test(`sandbox launcher starts nono despite a missing ${name}`, () => {
    const { root, home, cwd, agent, nono, profile } = fixture();
    const missing = join(root, "missing", name);
    const runtime = join(root, "runtime");
    mkdirSync(runtime);
    writeFileSync(nono, `#!${process.execPath}\nconsole.log(JSON.stringify(process.argv.slice(2)));\n`);
    chmodSync(nono, 0o700);
    const child = spawnSync(process.execPath, [
      new URL("../scripts/launcher.mjs", import.meta.url).pathname,
      nono, process.execPath, profile, "/missing-direnv", envBinary, "--version",
    ], {
      cwd,
      env: {
        HOME: home, PATH: process.env.PATH, PI_CODING_AGENT_DIR: agent,
        TMPDIR: runtime, XDG_RUNTIME_DIR: runtime, [name]: missing,
      },
      encoding: "utf8", timeout: 15000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
    assert.match(child.stderr, new RegExp(`${name}.*missing.*continuing without ${access}`));
    const args = JSON.parse(child.stdout);
    assert.equal(args[0], "run");
    assert.ok(args.includes("--profile"));
    assert.ok(!args.includes(missing));
    assert.deepEqual(args.slice(-2), [process.execPath, "--version"]);
  });
}

test("forged capability markers cannot bypass config errors", () => {
  const { launch, agent } = fixture();
  writeFileSync(join(agent, "settings.json"), "invalid JSON");
  for (const marker of [undefined, "/missing", "present"]) {
    assert.throws(() => launch(["--version"], { NONO_CAP_FILE: marker }), /Cannot load project references/);
  }
});

test("only leading explicit --no-sandbox bypasses policy; other placements reach nono", () => {
  const { launch, raw, nono, agent, profile } = fixture();
  writeFileSync(join(agent, "settings.json"), "invalid JSON");
  assert.deepEqual(launch(["--no-sandbox", "--print", "a b"], { NONO_CAP_FILE: "/forged" }), [raw, "--print", "a b"]);
  assert.throws(() => launch(["--", "--no-sandbox"]), /Cannot load project references/);
  assert.throws(() => launch(["--append-system-prompt", "--no-sandbox"]), /Cannot load project references/);
  rmSync(join(agent, "settings.json"));
  rmSync(profile);
  assert.throws(() => launch(["--version"]), /Nix nono profile missing/);
  assert.deepEqual(launch(["--no-sandbox", "--version"]), [raw, "--version"]);
  assert.notEqual(nono, raw);
});

test("global, trusted project and docs-cache references receive canonical read-only grants", () => {
  const { root, home, cwd, agent, raw, profile } = fixture();
  const target = join(root, "target");
  mkdirSync(target);
  symlinkSync(target, join(home, "nixos"));
  writeFileSync(join(agent, "settings.json"), JSON.stringify({ references: { nixos: { path: "~/nixos", description: "NixOS" } } }));
  mkdirSync(join(cwd, ".pi"));
  writeFileSync(join(cwd, ".pi", "settings.json"), JSON.stringify({ references: { project: { path: target, description: "project" } } }));
  mkdirSync(join(cwd, ".docs", "api"), { recursive: true });
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  const args = () => launchArguments(cwd, agent, home, {}, profile, raw, envBinary);
  assert.ok(values(args(), "--read").includes(realpathSync(target)));
  assert.ok(!values(args(), "--read").includes(realpathSync(join(cwd, ".docs", "api"))));
  writeFileSync(join(agent, "trust.json"), JSON.stringify({ [realpathSync(cwd)]: true }));
  assert.ok(values(args(), "--read").includes(realpathSync(join(cwd, ".docs", "api"))));
  assert.ok(!values(args(), "--allow").includes(realpathSync(target)));
  assert.ok(!values(args(), "--allow").includes(realpathSync(join(cwd, ".docs", "api"))));
  assert.ok(!values(args(), "--allow").includes(home));
});

test("retains narrow grants without Podman or SSH private-key access", () => {
  const { root, home, cwd, agent, raw, profile } = fixture();
  const config = join(root, "config");
  const data = join(root, "data");
  const cache = join(root, "cache");
  const allow = join(data, "direnv", "allow");
  const fff = join(cache, "nvim", "fff_nvim");
  const hashline = join(config, "pi-hashline-edit-pro");
  const known = join(home, ".ssh", "known_hosts");
  const connection = join(config, "containers", "podman-connections.json");
  const machine = join(data, "containers", "podman", "machine", "machine");
  const typo = join(config, "fbb", "data", "typos.abolish");
  const gitConfig = join(config, "nix", "git", "config");
  for (const path of [allow, fff, hashline, join(home, ".ssh"), join(config, "containers"), join(data, "containers", "podman", "machine"), join(config, "fbb", "data"), join(config, "nix", "git")]) mkdirSync(path, { recursive: true });
  for (const path of [known, connection, machine, typo, gitConfig]) writeFileSync(path, "fixture");
  const args = launchArguments(cwd, agent, home, { XDG_CONFIG_HOME: config, XDG_DATA_HOME: data, XDG_CACHE_HOME: cache }, profile, raw, envBinary);
  assert.ok(values(args, "--allow").includes(fff));
  assert.ok(values(args, "--allow").includes(hashline));
  assert.deepEqual(values(args, "--read"), [realpathSync(allow)]);
  assert.ok(!values(args, "--allow").includes(realpathSync(join(data, "direnv"))));
  assert.ok(!values(args, "--allow").includes(realpathSync(allow)));
  assert.deepEqual(values(args, "--read-file"), [known, typo, gitConfig]);
  assert.deepEqual(values(args, "--bypass-protection"), [known]);
  assert.ok(!values(args, "--read").includes(join(home, ".ssh")));
  assert.ok(!values(args, "--allow").includes(join(home, ".ssh")));
  assert.ok(!values(args, "--allow").includes(config));
});

test("missing XDG_RUNTIME_DIR paths warn without creating directories or adding grants", t => {
  const { root, launch } = fixture();
  const expected = launch();
  const warning = t.mock.method(console, "warn", () => {});
  const missing = join(root, "missing-runtime");
  const dangling = join(root, "dangling-runtime");
  symlinkSync(missing, dangling);
  const directories = [missing, join(root, "missing-session", "runtime"), dangling];
  for (const directory of directories) {
    assert.deepEqual(launch([], { XDG_RUNTIME_DIR: directory }), expected);
    assert.equal(existsSync(directory), false);
  }
  assert.equal(warning.mock.callCount(), directories.length);
  for (const [index, call] of warning.mock.calls.entries()) {
    assert.match(call.arguments[0], /XDG_RUNTIME_DIR.*missing.*continuing without runtime-directory access/);
    assert.ok(call.arguments[0].includes(JSON.stringify(directories[index])));
  }
});

test("an existing non-directory XDG_RUNTIME_DIR still fails closed", () => {
  const { root, launch } = fixture();
  const file = join(root, "not-a-directory");
  writeFileSync(file, "fixture");
  assert.throws(() => launch([], { XDG_RUNTIME_DIR: file }), /Not a directory/);
});

test("does not create or grant writable direnv trust state while permitting the selected runtime root", () => {
  const { root, home, cwd, agent, raw, profile } = fixture();
  const data = join(root, "data");
  const runtime = join(root, "runtime");
  mkdirSync(runtime);
  const environment = { XDG_DATA_HOME: data, XDG_RUNTIME_DIR: runtime };
  const args = launchArguments(cwd, agent, home, environment, profile, raw, envBinary);
  const state = join(data, "direnv");
  assert.equal(existsSync(state), false);
  assert.ok(!values(args, "--allow").includes(state));
  assert.ok(values(args, "--allow").includes(realpathSync(runtime)));
  assert.ok(!values(args, "--allow").includes(data));
  assert.ok(!values(args, "--allow").includes(home));

  const approvals = join(state, "allow");
  mkdirSync(approvals, { recursive: true });
  const approvedArgs = launchArguments(cwd, agent, home, environment, profile, raw, envBinary);
  assert.ok(values(approvedArgs, "--read").includes(realpathSync(approvals)));
  assert.ok(!values(approvedArgs, "--allow").includes(realpathSync(approvals)));
  assert.ok(!values(approvedArgs, "--allow").includes(realpathSync(state)));
});

test("global user skills do not require project trust", () => {
  const { home, agent, raw, profile } = fixture();
  const cwd = join(home, "project");
  const docs = join(cwd, ".docs", "api");
  mkdirSync(join(home, ".agents", "skills"), { recursive: true });
  mkdirSync(docs, { recursive: true });
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  assert.ok(values(launchArguments(cwd, agent, home, {}, profile, raw, envBinary), "--read").includes(realpathSync(docs)));
});

test("nearest trust decisions win and invalid trust data fails closed", () => {
  const { root, cwd, agent, launch } = fixture();
  const docs = join(cwd, ".docs", "api");
  mkdirSync(join(cwd, ".pi"));
  writeFileSync(join(cwd, ".pi", "settings.json"), "{}");
  mkdirSync(docs, { recursive: true });
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  const trust = join(agent, "trust.json");
  writeFileSync(trust, JSON.stringify({ [realpathSync(root)]: true, [realpathSync(cwd)]: false }));
  assert.ok(!values(launch(), "--read").includes(realpathSync(docs)));
  writeFileSync(trust, `\uFEFF${JSON.stringify({ [realpathSync(root)]: true, [realpathSync(cwd)]: null })}`);
  assert.ok(values(launch(), "--read").includes(realpathSync(docs)));
  for (const invalid of [[], null, { [realpathSync(root)]: true, [realpathSync(cwd)]: "yes" }]) {
    writeFileSync(trust, JSON.stringify(invalid));
    assert.throws(() => launch(), /Invalid project trust store/);
  }
});

test("current-directory references are removed before collision checks", () => {
  const { cwd, agent, launch } = fixture();
  const docs = join(cwd, ".docs", "api");
  mkdirSync(docs, { recursive: true });
  writeFileSync(join(agent, "settings.json"), JSON.stringify({ references: { api: { path: cwd, description: "current project" } } }));
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  assert.ok(values(launch(), "--read").includes(realpathSync(docs)));
});

test("built entry cannot source shell or Node preload code before confinement", { skip: !process.env.PI_TEST_BINARY }, () => {
  const { root, home, cwd, agent } = fixture();
  const marker = join(root, "executed");
  const shell = join(root, "preload.sh");
  const preload = join(root, "preload.mjs");
  writeFileSync(shell, `printf injected > '${marker}'\n`);
  writeFileSync(preload, `import { writeFileSync } from 'node:fs'; writeFileSync(${JSON.stringify(marker)}, 'injected');\n`);
  writeFileSync(join(agent, "settings.json"), "invalid JSON");
  const child = spawnSync(process.env.PI_TEST_BINARY, ["--version"], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, HOME: home, PI_CODING_AGENT_DIR: agent, BASH_ENV: shell, NODE_OPTIONS: `--import=${preload}`, NODE_PATH: root },
  });
  assert.ifError(child.error);
  assert.equal(child.status, 1);
  assert.match(child.stderr, /Cannot load project references/);
  assert.equal(existsSync(marker), false);
});

test("sandbox startup suppresses only the proxy-agent warning and preserves proxy settings", () => {
  const { root, home, cwd, agent, nono, profile } = fixture();
  const runtime = join(root, "runtime");
  mkdirSync(runtime);
  const launcher = new URL("../scripts/launcher.mjs", import.meta.url).pathname;
  writeFileSync(profile, readFileSync(new URL("../scripts/profile.json", import.meta.url)));
  writeFileSync(nono, `#!${process.execPath}
    const { spawnSync } = require("node:child_process");
    const command = process.argv.slice(process.argv.indexOf("--") + 1);
    const environment = { ...process.env, NODE_USE_ENV_PROXY: "1", HTTPS_PROXY: "http://127.0.0.1:1" };
    delete environment.NODE_OPTIONS;
    delete environment.NODE_PATH;
    const child = spawnSync(command[0], command.slice(1), {
      stdio: "inherit",
      env: environment,
    });
    if (child.error) throw child.error;
    process.exit(child.status ?? 1);
  `);
  chmodSync(nono, 0o700);
  const probe = `
    process.emitWarning("proxy-agent notice", { code: "UNDICI-EHPA" });
    process.emitWarning("other warning", { code: "PI_TEST_OTHER_WARNING" });
    console.log(JSON.stringify({
      useEnvProxy: process.env.NODE_USE_ENV_PROXY,
      httpsProxy: process.env.HTTPS_PROXY,
      nodeOptions: process.env.NODE_OPTIONS,
      nodePath: process.env.NODE_PATH,
    }));
  `;
  for (const sandboxed of [true, false]) {
    const child = spawnSync(process.execPath, [
      launcher, nono, process.execPath, profile, "/missing-direnv", envBinary,
      ...(sandboxed ? [] : ["--no-sandbox"]), "-e", probe,
    ], {
      cwd,
      env: { HOME: home, PATH: process.env.PATH, TMPDIR: runtime, XDG_RUNTIME_DIR: runtime, PI_CODING_AGENT_DIR: agent, NODE_OPTIONS: "--trace-warnings", NODE_PATH: root },
      encoding: "utf8",
      timeout: 15000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
    assert.equal(child.stderr.includes("UNDICI-EHPA"), !sandboxed, child.stderr);
    assert.match(child.stderr, /PI_TEST_OTHER_WARNING/);
    assert.deepEqual(JSON.parse(child.stdout), sandboxed ? {
      useEnvProxy: "1",
      httpsProxy: "http://127.0.0.1:1",
      nodeOptions: "--disable-warning=UNDICI-EHPA",
    } : {});
  }
});

test("direct SSH/web exceptions and proxy flags are scoped across OS paths", () => {
  const { cwd, agent, home, raw, profile } = fixture();
  const policy = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  assert.deepEqual(policy.network.open_port, [9222, 2828]);
  assert.deepEqual(policy.network.credentials, ["github"]);
  assert.deepEqual(policy.network.custom_credentials.github, {
    upstream: "https://api.github.com", credential_key: "cmd://github", env_var: "GH_TOKEN",
  });
  assert.deepEqual(policy.credential_capture.github.command, ["@GH_CAPTURE_BIN@", "auth", "token", "--hostname", "github.com"]);
  assert.ok(!policy.filesystem.read.includes("$HOME/.config/gh"));
  assert.ok(policy.filesystem.read.includes("$HOME/.local/share/gh/extensions"));
  const darwin = launchArguments(cwd, agent, home, {}, profile, raw, envBinary, "darwin");
  const linux = launchArguments(cwd, agent, home, {}, profile, raw, envBinary, "linux");
  assert.ok(darwin.includes("--trust-proxy-ca"));
  assert.ok(!linux.includes("--trust-proxy-ca"));
  assert.equal(policy.linux.sandbox_policy, "landlock");
  assert.deepEqual(values(linux, "--allow-connect-port"), ["22", "80", "443"]);
  assert.deepEqual(values(darwin, "--allow-connect-port"), []);
  assert.deepEqual(policy.network.allow_domain ?? [], []);
});

test("dynamic grants reject the GitHub store through runtime, reference, cwd, and symlink aliases", () => {
  const { root, home, agent, cwd, raw, profile } = fixture();
  const config = join(home, ".config");
  const store = join(config, "gh");
  mkdirSync(store, { recursive: true });
  const args = (directory, env = {}) => launchArguments(directory, agent, home, env, profile, raw, envBinary);
  assert.throws(() => args(cwd, { XDG_RUNTIME_DIR: store }), /GitHub credential/);
  writeFileSync(join(agent, "settings.json"), JSON.stringify({ references: { config: { path: config, description: "fixture" } } }));
  assert.throws(() => args(cwd), /GitHub credential/);
  rmSync(join(agent, "settings.json"));
  assert.throws(() => args(store), /GitHub credential/);
  const alias = join(root, "config-alias");
  symlinkSync(config, alias);
  assert.throws(() => args(cwd, { XDG_RUNTIME_DIR: alias }), /GitHub credential/);
  const target = join(root, "credential-target");
  writeFileSync(target, "synthetic");
  symlinkSync(target, join(store, "hosts.yml"));
  const targetParent = join(root, "target-parent");
  mkdirSync(targetParent);
  const linkedTarget = join(targetParent, "hosts.yml");
  rmSync(join(store, "hosts.yml"));
  symlinkSync(linkedTarget, join(store, "hosts.yml"));
  writeFileSync(linkedTarget, "synthetic");
  assert.throws(() => args(cwd, { XDG_RUNTIME_DIR: targetParent }), /GitHub credential/);
  assert.doesNotThrow(() => args(cwd, { XDG_RUNTIME_DIR: join(home, ".pi", "agent") }));
});

test("sandbox handoff uses literal assignments and does not load shell or Node preloads", () => {
  const { root } = fixture();
  const home = join(root, "hjem æøå ' \" $()\n");
  const marker = join(root, "executed");
  const shell = join(root, "preload.sh");
  const preload = join(root, "preload.mjs");
  writeFileSync(shell, `printf injected > '${marker}'\n`);
  writeFileSync(preload, `import { writeFileSync } from "node:fs"; writeFileSync(${JSON.stringify(marker)}, "injected");\n`);
  const literals = ["a prompt with spaces", "", "--no-sandbox", "'; touch injected", "æøå", "key=value"];
  const probe = `
    const names = ["GH_CONFIG_DIR", "npm_config_cache", "UV_CACHE_DIR", "UV_PYTHON_INSTALL_DIR", "UV_TOOL_DIR", "NODE_OPTIONS", "GH_TOKEN", "HTTPS_PROXY"];
    console.log(JSON.stringify({ pid: process.pid, args: process.argv.slice(1), environment: Object.fromEntries(names.map(name => [name, process.env[name]])) }));
  `;
  const command = sandboxRuntimeCommand(home, process.execPath, envBinary);
  assert.equal(command[0], envBinary);
  const child = spawnSync(command[0], [...command.slice(1), "-e", probe, "--", ...literals], {
    env: {
      ...process.env, PATH: "/untrusted", HOME: home, BASH_ENV: shell, ENV: shell,
      NODE_OPTIONS: `--import=${preload}`, GH_CONFIG_DIR: "/host/credentials",
      GH_TOKEN: "synthetic-proxy-placeholder", HTTPS_PROXY: "http://127.0.0.1:12345",
    },
    encoding: "utf8", timeout: 15000,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  const result = JSON.parse(child.stdout);
  assert.equal(result.pid, child.pid);
  assert.deepEqual(result.args, literals);
  assert.deepEqual(result.environment, {
    GH_CONFIG_DIR: join(home, ".cache", "pi", "gh"),
    npm_config_cache: join(home, ".cache", "pi", "npm"),
    UV_CACHE_DIR: join(home, ".cache", "pi", "uv"),
    UV_PYTHON_INSTALL_DIR: join(home, ".cache", "pi", "uv-python"),
    UV_TOOL_DIR: join(home, ".cache", "pi", "uv-tools"),
    NODE_OPTIONS: "--disable-warning=UNDICI-EHPA",
    GH_TOKEN: "synthetic-proxy-placeholder", HTTPS_PROXY: "http://127.0.0.1:12345",
  });
  assert.equal(existsSync(marker), false);
});

test("sandbox handoff preserves child exit status and terminating signal", () => {
  const { home } = fixture();
  const command = sandboxRuntimeCommand(home, process.execPath, envBinary);
  for (const [probe, status, signal] of [
    ["process.exit(7)", 7, null],
    ['process.kill(process.pid, "SIGTERM")', null, "SIGTERM"],
  ]) {
    const child = spawnSync(command[0], [...command.slice(1), "-e", probe], { encoding: "utf8", timeout: 15000 });
    assert.ifError(child.error);
    assert.equal(child.status, status, child.stderr);
    assert.equal(child.signal, signal, child.stderr);
  }
});

test("sandbox launches require the pinned env executable while direct launches bypass it", () => {
  const { cwd, agent, home, nono, raw, profile } = fixture();
  for (const missing of ["env", join(home, "missing-env"), home]) {
    assert.throws(() => launchArguments(cwd, agent, home, {}, profile, raw, missing), /Nix env executable missing/);
  }
  assert.deepEqual(launchCommand(["--no-sandbox", "--version"], cwd, agent, home, {}, nono, raw, profile, "/missing-env"), [raw, "--version"]);
});
