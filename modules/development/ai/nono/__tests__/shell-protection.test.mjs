import { afterEach, test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { shellProtection, withProtectedShellProfile } from "../scripts/shell-protection.mjs";

const created = [];
const baseProfile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));

function fixture(name = "home") {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-shell-protection-")));
  created.push(root);
  const home = join(root, name);
  const source = join(home, "dotfiles", ".config", "fish");
  const config = join(home, ".config", "fish");
  const cache = join(home, ".cache", "fish");
  for (const path of [source, config, cache, join(home, ".pi", "agent")]) mkdirSync(path, { recursive: true });
  writeFileSync(join(source, "config.fish"), "# startup fixture\n");
  symlinkSync(join(source, "config.fish"), join(config, "config.fish"));
  writeFileSync(join(home, "dotfiles", ".shinit"), "# dash fixture\n");
  symlinkSync(join(home, "dotfiles", ".shinit"), join(home, ".shinit"));
  writeFileSync(join(cache, "atuin-init.fish"), "# cache fixture\n");
  const environment = {
    ...process.env,
    HOME: home,
    PI_CODING_AGENT_DIR: join(home, ".pi", "agent"),
    XDG_CONFIG_HOME: join(home, ".config"),
    XDG_CACHE_HOME: join(home, ".cache"),
    XDG_DATA_HOME: join(home, ".local", "share"),
    XDG_STATE_HOME: join(home, ".local", "state"),
    XDG_RUNTIME_DIR: root,
    TMPDIR: root,
  };
  return { root, home, source, config, cache, environment };
}

afterEach(() => {
  for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true });
});

function hasFilter(protection, kind, path) {
  return protection.rules.some((rule) => rule.includes(`(${kind} ${JSON.stringify(path)})`));
}

test("protects live and Stow startup trees, caches, missing inputs and ancestor replacement without freezing siblings", () => {
  const { home, source, config, cache } = fixture();
  const protection = shellProtection(home);
  for (const path of [source, config, cache, join(home, ".shinit"), join(home, "dotfiles", ".shinit"), join(home, ".inshellisense", "key-bindings.fish"), join(home, ".config", "starship.toml")]) {
    assert.ok(hasFilter(protection, "subpath", path), path);
  }
  for (const path of [home, dirname(config), dirname(source), join(home, "dotfiles")]) {
    assert.ok(hasFilter(protection, "literal", path), path);
    assert.ok(!hasFilter(protection, "subpath", path), path);
  }
  assert.ok(protection.readPaths.includes(source));
  assert.ok(protection.readPaths.includes(config));
  assert.ok(hasFilter(protection, "subpath", protection.profileDirectory));
  assert.ok(protection.rules.every((rule) => rule.startsWith("(deny file-write* ")));
});

test("protects every symlink hop, external function targets, and dangling targets", () => {
  const { root, home, config } = fixture();
  const target = join(root, "external-functions");
  const hop = join(root, "function-link");
  mkdirSync(target);
  writeFileSync(join(target, "helper.fish"), "# helper\n");
  symlinkSync(target, hop);
  symlinkSync(hop, join(config, "functions"));
  const missing = join(root, "not-created", "snippet.fish");
  symlinkSync(missing, join(config, "snippet.fish"));
  const protection = shellProtection(home);
  assert.ok(hasFilter(protection, "literal", hop));
  assert.ok(hasFilter(protection, "subpath", target));
  assert.ok(hasFilter(protection, "subpath", missing));
  assert.ok(hasFilter(protection, "literal", dirname(missing)));
  assert.ok(protection.readPaths.includes(target));
});

test("resolves parent components after symlinks and rejects ambiguous missing prefixes", () => {
  const { root, home, config } = fixture();
  const directory = join(root, "other", "directory");
  const bridge = join(root, "bridge");
  const alias = join(config, "external.fish");
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(dirname(directory), "startup.fish"), "# external startup");
  symlinkSync(directory, bridge);
  symlinkSync(`${bridge}/../startup.fish`, alias);
  const target = realpathSync.native(alias);
  const protection = shellProtection(home);
  assert.ok(hasFilter(protection, "subpath", target), target);
  assert.ok(hasFilter(protection, "literal", bridge));
  assert.ok(hasFilter(protection, "literal", directory));
  assert.ok(protection.readPaths.includes(target));
  rmSync(alias);
  symlinkSync(`${root}/missing/../startup.fish`, alias);
  assert.throws(() => shellProtection(home), /parent traversal/);
});

test("protects symlinked config ancestors without denying their whole target directory", () => {
  const { root, home } = fixture();
  const config = join(root, "xdg-config");
  const hop = join(root, "xdg-link");
  mkdirSync(join(config, "fish"), { recursive: true });
  symlinkSync(config, hop);
  const protection = shellProtection(home, { XDG_CONFIG_HOME: hop });
  assert.ok(hasFilter(protection, "literal", hop));
  assert.ok(hasFilter(protection, "literal", config));
  assert.ok(hasFilter(protection, "subpath", join(config, "fish")));
  assert.ok(!hasFilter(protection, "subpath", config));
});

test("escapes Seatbelt strings and preserves Danish paths", () => {
  const { home } = fixture('æøå "quoted" \\ directory');
  const protection = shellProtection(home);
  assert.ok(hasFilter(protection, "literal", home));
  assert.ok(protection.rules.join("").includes("æøå"));
});

test("rejects symlink loops, hard-linked startup files, home-ancestor targets, and relative XDG paths", () => {
  const { root, home, source, config } = fixture();
  assert.throws(() => shellProtection(home, { XDG_CONFIG_HOME: "relative" }), /must be absolute/);
  const alias = join(root, "hardlink");
  linkSync(join(source, "config.fish"), alias);
  assert.throws(() => shellProtection(home), /Hard-linked startup file/);
  rmSync(alias);
  const loop = join(config, "loop");
  symlinkSync(loop, loop);
  assert.throws(() => shellProtection(home), /Too many startup symlinks/);
  rmSync(loop);
  symlinkSync(home, loop);
  assert.throws(() => shellProtection(home), /home ancestor/);
});

test("rejects unrepresentable startup paths", () => {
  const { home } = fixture("invalid\nname");
  assert.throws(() => shellProtection(home), /control character/);
});

test("generated profile preserves base permissions, appends denials, and cleans up after success and failure", () => {
  const { home, environment } = fixture();
  const original = readFileSync(baseProfile, "utf8");
  for (const fail of [false, true]) {
    let generated;
    const run = () => withProtectedShellProfile(baseProfile, home, environment, (path) => {
      generated = path;
      const actual = JSON.parse(readFileSync(path, "utf8"));
      const expected = JSON.parse(original);
      assert.deepEqual(actual.filesystem.allow, expected.filesystem.allow);
      assert.deepEqual(actual.network, expected.network);
      assert.deepEqual(actual.security, expected.security);
      assert.deepEqual(actual.unsafe_macos_seatbelt_rules.slice(0, -1), expected.unsafe_macos_seatbelt_rules);
      assert.match(actual.unsafe_macos_seatbelt_rules.at(-1), /^\(deny file-write\*/);
      assert.ok(path.startsWith(join(realpathSync(home), ".local", "state", "nono", "pi-profiles")));
      assert.equal(statSync(path).mode & 0o777, 0o600);
      assert.equal(statSync(dirname(path)).mode & 0o777, 0o700);
      if (fail) throw new Error("fixture child failed");
      return 17;
    }, "darwin");
    if (fail) assert.throws(run, /fixture child failed/);
    else assert.equal(run(), 17);
    assert.ok(!existsSync(dirname(generated)));
    assert.equal(readFileSync(baseProfile, "utf8"), original);
  }
});

test("refuses symlinked and shared profile-state ancestors before launching", () => {
  for (const type of ["symlink", "shared"]) {
    const { root, home, environment } = fixture();
    const local = join(home, ".local");
    if (type === "symlink") symlinkSync(root, local);
    else { mkdirSync(local); chmodSync(local, 0o777); }
    assert.throws(() => withProtectedShellProfile(baseProfile, home, environment, () => assert.fail("must not launch"), "darwin"), /Unsafe Pi profile directory/);
  }
});

test("malformed base policy fails closed and Linux retains its existing profile without claiming selective protection", () => {
  const { root, home } = fixture();
  const profile = join(root, "invalid.json");
  for (const value of ["invalid JSON", "null", '{"filesystem":null}', '{"filesystem":{"read":null}}', '{"unsafe_macos_seatbelt_rules":null}']) {
    writeFileSync(profile, value);
    assert.throws(() => withProtectedShellProfile(profile, home, {}, () => assert.fail("must not launch"), "darwin"));
  }
  assert.equal(withProtectedShellProfile(profile, home, {}, (path) => path, "linux"), profile);
  assert.ok(!existsSync(join(home, ".local")));
});

test("launcher supplies the generated policy to nono and --no-sandbox skips protection setup", { skip: process.platform !== "darwin" }, () => {
  const { root, home, environment } = fixture();
  const nono = join(root, "nono-fixture.mjs");
  writeFileSync(nono, `#!${process.execPath}\nimport {readFileSync} from 'node:fs';const p=process.argv[process.argv.indexOf('--profile')+1];console.log(JSON.stringify({path:p,profile:JSON.parse(readFileSync(p,'utf8'))}));\n`, { mode: 0o700 });
  const child = spawnSync(process.execPath, [launcher, nono, "/usr/bin/true", baseProfile], { cwd: root, env: environment, encoding: "utf8" });
  assert.equal(child.status, 0, child.stderr);
  const actual = JSON.parse(child.stdout);
  assert.match(actual.profile.unsafe_macos_seatbelt_rules.at(-1), /^\(deny file-write\*/);
  assert.ok(!existsSync(actual.path));
  assert.deepEqual(readdirSync(join(home, ".local", "state", "nono", "pi-profiles")), []);
  rmSync(join(home, ".local"), { recursive: true });
  symlinkSync(root, join(home, ".local"));
  const direct = spawnSync(process.execPath, [launcher, "/missing-nono", "/usr/bin/true", "/missing-profile", "--no-sandbox"], { cwd: root, env: environment, encoding: "utf8" });
  assert.equal(direct.status, 0, direct.stderr);
  assert.ok(!existsSync(join(root, "state")));
});

test("installed nono accepts a generated startup protection profile", { skip: !process.env.NONO_PROFILE_TEST_BINARY }, () => {
  const { home, environment } = fixture();
  withProtectedShellProfile(baseProfile, home, environment, (profile) => {
    const child = spawnSync(process.env.NONO_PROFILE_TEST_BINARY, ["profile", "validate", profile], { env: environment, encoding: "utf8" });
    assert.equal(child.status, 0, child.stderr || child.stdout);
  }, "darwin");
});

test("fresh macOS nono denies startup mutations and inherited bypasses while preserving ordinary edits", {
  skip: process.platform !== "darwin" || !process.env.NONO_TEST_BINARY,
}, () => {
  const { root, home, source, environment } = fixture();
  // Nono refuses grants overlapping its own state; keep that state outside the writable fixture.
  const state = mkdtempSync(join(process.cwd(), ".pi-shell-state-"));
  created.push(state);
  const sandboxEnvironment = { ...process.env, XDG_STATE_HOME: state };
  const probe = join(root, "probe.mjs");
  writeFileSync(probe, readFileSync(new URL("./fixtures/shell-protection-probe.mjs", import.meta.url)));
  withProtectedShellProfile(baseProfile, home, environment, (profile) => {
    const originalPolicy = readFileSync(profile, "utf8");
    const child = spawnSync(process.env.NONO_TEST_BINARY, [
      "run", "--profile", profile, "--allow", root, "--allow-cwd", "--",
      process.execPath, probe, home, profile,
    ], { cwd: root, env: sandboxEnvironment, encoding: "utf8", timeout: 30000 });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr || child.stdout);
    assert.equal(readFileSync(profile, "utf8"), originalPolicy);
  }, "darwin");
  const startup = join(source, "config.fish");
  assert.equal(readFileSync(startup, "utf8"), "# startup fixture\n");
  writeFileSync(startup, "# unsandboxed edit\n");
  assert.equal(readFileSync(startup, "utf8"), "# unsandboxed edit\n");
});
