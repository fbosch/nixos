import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { launchArguments, launchCommand, prepareJitiCache } from "../scripts/launcher.mjs";

test("profile grants Jiti cache reads without allowing reads throughout tmp", () => {
  const profile = JSON.parse(readFileSync(new URL("../scripts/profile.json", import.meta.url), "utf8"));
  assert.ok(profile.filesystem.read.includes("$TMPDIR/jiti"));
  for (const paths of [profile.filesystem.read, profile.filesystem.allow]) {
    assert.ok(!paths.includes("/tmp"));
    assert.ok(!paths.includes("$TMPDIR"));
  }
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
  for (const path of [nono, raw, profile]) writeFileSync(path, "fixture");
  const launch = (args = [], env = {}) => launchCommand(args, cwd, agent, home, env, nono, raw, profile);
  return { root, home, agent, cwd, nono, raw, profile, launch };
}
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });
function values(args, flag) {
  return args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
}

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

test("Linux profile permits Jiti cache write/read cycles but denies unrelated temporary-file reads", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  const { root, cwd } = fixture();
  const temporary = join(root, "temporary");
  prepareJitiCache(temporary, "linux");
  const cache = join(temporary, "jiti", "extension.mjs");
  const outside = join(temporary, "unrelated");
  writeFileSync(outside, "private fixture");
  const child = spawnSync(process.env.NONO_TEST_BINARY, [
    "run", "--profile", new URL("../scripts/profile.json", import.meta.url).pathname, "--allow-cwd", "--",
    process.execPath, "-e", `
      const fs = require("node:fs");
      const assert = require("node:assert/strict");
      fs.writeFileSync(process.argv[1], "compiled extension");
      assert.equal(fs.readFileSync(process.argv[1], "utf8"), "compiled extension");
      assert.throws(() => fs.readFileSync(process.argv[2]), { code: "EACCES" });
    `, cache, outside,
  ], { cwd, env: { ...process.env, TMPDIR: temporary }, encoding: "utf8" });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
});

test("always selects absolute nono, immutable profile and distinct raw Pi, preserving argv", () => {
  const { launch, nono, raw, profile } = fixture();
  const args = ["--print", "a prompt with spaces", "--", "--no-sandbox"];
  const command = launch(args, { NONO_CAP_FILE: "/forged/capability.json" });
  assert.equal(command[0], nono);
  assert.deepEqual(command.slice(1, 4), ["run", "--profile", profile]);
  assert.deepEqual(command.slice(-args.length - 2), ["--", raw, ...args]);
  assert.notEqual(command[0], raw);
  assert.ok(command.includes("--allow-cwd"));
  assert.deepEqual(values(command, "--suppress-save-prompt"), ["/"]);
});

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

test("global, trusted project and docs-cache references retain canonical writable grants", () => {
  const { root, home, cwd, agent, raw, profile } = fixture();
  const target = join(root, "target");
  mkdirSync(target);
  symlinkSync(target, join(home, "nixos"));
  writeFileSync(join(agent, "settings.json"), JSON.stringify({ references: { nixos: { path: "~/nixos", description: "NixOS" } } }));
  mkdirSync(join(cwd, ".pi"));
  writeFileSync(join(cwd, ".pi", "settings.json"), JSON.stringify({ references: { project: { path: target, description: "project" } } }));
  mkdirSync(join(cwd, ".docs", "api"), { recursive: true });
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  const grants = () => values(launchArguments(cwd, agent, home, {}, profile, raw), "--allow");
  assert.ok(grants().includes(realpathSync(target)));
  assert.ok(!grants().includes(realpathSync(join(cwd, ".docs", "api"))));
  writeFileSync(join(agent, "trust.json"), JSON.stringify({ [realpathSync(cwd)]: true }));
  assert.ok(grants().includes(realpathSync(join(cwd, ".docs", "api"))));
  assert.ok(!grants().includes(home));
});

test("retains direnv, FFF, hashline, read-only aliases and Podman narrow grants", () => {
  const { root, home, cwd, agent, raw, profile } = fixture();
  const config = join(root, "config");
  const data = join(root, "data");
  const cache = join(root, "cache");
  const allow = join(data, "direnv", "allow");
  const fff = join(cache, "nvim", "fff_nvim");
  const hashline = join(config, "pi-hashline-edit-pro");
  const known = join(home, ".ssh", "known_hosts");
  const connection = join(config, "containers", "podman-connections.json");
  const typo = join(config, "fbb", "data", "typos.abolish");
  for (const path of [allow, fff, hashline, join(home, ".ssh"), join(config, "containers"), join(config, "fbb", "data")]) mkdirSync(path, { recursive: true });
  for (const path of [known, connection, typo]) writeFileSync(path, "fixture");
  const args = launchArguments(cwd, agent, home, { XDG_CONFIG_HOME: config, XDG_DATA_HOME: data, XDG_CACHE_HOME: cache }, profile, raw);
  assert.ok(values(args, "--allow").includes(fff));
  assert.ok(values(args, "--allow").includes(hashline));
  assert.deepEqual(values(args, "--read"), [allow]);
  for (const path of [connection, known, typo]) assert.ok(values(args, "--read-file").includes(path));
  assert.deepEqual(values(args, "--bypass-protection"), [known]);
  assert.ok(!values(args, "--allow").includes(config));
});

test("global user skills do not require project trust", () => {
  const { home, agent, raw, profile } = fixture();
  const cwd = join(home, "project");
  const docs = join(cwd, ".docs", "api");
  mkdirSync(join(home, ".agents", "skills"), { recursive: true });
  mkdirSync(docs, { recursive: true });
  writeFileSync(join(cwd, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  assert.ok(values(launchArguments(cwd, agent, home, {}, profile, raw), "--allow").includes(realpathSync(docs)));
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
  assert.ok(!values(launch(), "--allow").includes(realpathSync(docs)));
  writeFileSync(trust, `\uFEFF${JSON.stringify({ [realpathSync(root)]: true, [realpathSync(cwd)]: null })}`);
  assert.ok(values(launch(), "--allow").includes(realpathSync(docs)));
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
  assert.ok(values(launch(), "--allow").includes(realpathSync(docs)));
});

test("built entry cannot source shell or Node preload code before confinement", { skip: !process.env.PI_TEST_BINARY }, () => {
  const { root, cwd, agent } = fixture();
  const marker = join(root, "executed");
  const shell = join(root, "preload.sh");
  const preload = join(root, "preload.mjs");
  writeFileSync(shell, `printf injected > '${marker}'\n`);
  writeFileSync(preload, `import { writeFileSync } from 'node:fs'; writeFileSync(${JSON.stringify(marker)}, 'injected');\n`);
  writeFileSync(join(agent, "settings.json"), "invalid JSON");
  const child = spawnSync(process.env.PI_TEST_BINARY, ["--version"], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, PI_CODING_AGENT_DIR: agent, BASH_ENV: shell, NODE_OPTIONS: `--import=${preload}`, NODE_PATH: root },
  });
  assert.ifError(child.error);
  assert.equal(child.status, 1);
  assert.match(child.stderr, /Cannot load project references/);
  assert.equal(existsSync(marker), false);
});
