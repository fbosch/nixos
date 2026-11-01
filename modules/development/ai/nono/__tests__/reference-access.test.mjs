import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { launchArguments, referenceApprovalStore } from "../scripts/launcher.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const created = [];
// Landlock cannot exclude shell startup paths from a writable grant, so Linux splits dotfiles grants.
const linux = process.platform === "linux";

// Keep fixture HOME outside the shared temporary-directory read grants.
function fixture(base = process.cwd()) {
  const root = realpathSync(mkdtempSync(join(base, ".pi-reference-test-")));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const project = join(home, "project");
  const dotfiles = join(home, "dotfiles");
  const nixos = join(home, "nixos");
  const vault = join(root, "vault");
  const temporary = join(root, "tmp");
  const runtime = join(root, "runtime");
  for (const path of [agent, project, dotfiles, nixos, vault, temporary, runtime]) mkdirSync(path, { recursive: true });
  const settings = join(agent, "settings.json");
  writeFileSync(settings, JSON.stringify({ references: {
    dotfiles: { path: "~/dotfiles", description: "Dotfiles" },
    nixos: { path: "~/nixos", description: "NixOS" },
    vault: { path: vault, description: "Vault" },
  } }));
  // Approvals are host-only state; the fixture approves its external vault as the user would.
  const approve = (...paths) => {
    const store = referenceApprovalStore(home);
    mkdirSync(dirname(store), { recursive: true, mode: 0o700 });
    writeFileSync(store, JSON.stringify(paths), { mode: 0o600 });
    return store;
  };
  approve(vault);
  const args = (cwd = project, environment = {}) => launchArguments(cwd, agent, home, { TMPDIR: temporary, XDG_RUNTIME_DIR: runtime, ...environment }, profile, process.execPath, envBinary);
  return { root, home, agent, project, dotfiles, nixos, vault, settings, temporary, runtime, approve, args };
}

afterEach(() => {
  for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true });
});

function paths(args, flag) {
  return args.flatMap((value, index) => value === flag ? [args[index + 1]] : []);
}

function assertReadOnly(args, targets) {
  for (const target of targets) {
    assert.ok(paths(args, "--read").includes(realpathSync(target)), target);
    assert.ok(!paths(args, "--allow").includes(realpathSync(target)), target);
  }
}

// Production writes this profile in credential-proxy's sandboxCommand whenever the launcher withholds --allow-cwd.
function withoutWorkdirGrant(f, args) {
  if (args.includes("--allow-cwd")) return args;
  const path = join(f.root, `sandbox-${Math.random().toString(16).slice(2)}.json`);
  writeFileSync(path, JSON.stringify({ ...JSON.parse(readFileSync(profile, "utf8")), workdir: { access: "none" } }));
  const result = [...args];
  result[result.indexOf("--profile") + 1] = path;
  return result;
}

function liveEnvironment(f) {
  return {
    ...process.env,
    HOME: f.home,
    PI_CODING_AGENT_DIR: f.agent,
    XDG_CONFIG_HOME: join(f.home, ".config"),
    XDG_DATA_HOME: join(f.home, ".local", "share"),
    XDG_CACHE_HOME: join(f.home, ".cache"),
    XDG_STATE_HOME: join(f.root, "state"),
    TMPDIR: f.temporary,
    PI_HASHLINE_DIR: join(f.home, ".config", "pi-hashline-edit-pro"),
    FFF_FRECENCY_DB: join(f.home, ".cache", "fff"),
    FFF_HISTORY_DB: join(f.home, ".local", "share", "fff"),
  };
}

test("references stay read-only outside the paired repositories while cwd remains writable", () => {
  const f = fixture();
  const args = f.args();
  assertReadOnly(args, [f.dotfiles, f.nixos, f.vault]);
  assert.ok(args.includes("--allow-cwd"));
});

for (const name of ["dotfiles", "nixos"]) {
  for (const nested of [false, true]) {
    test(`${name}${nested ? " subdirectory" : " root"} enables only paired repository references for writes`, () => {
      const f = fixture();
      const cwd = nested ? join(f[name], "nested") : f[name];
      mkdirSync(cwd, { recursive: true });
      const args = f.args(cwd);
      assertReadOnly(args, [f.vault]);
      for (const target of [f.dotfiles, f.nixos]) {
        // dotfiles contains shell startup paths, so Linux grants its entries instead of its root.
        const split = linux && target === f.dotfiles;
        if (target === cwd) {
          assert.equal(args.includes("--allow-cwd"), !split);
          assert.equal(paths(args, "--read").includes(target), split);
        } else {
          assert.equal(paths(args, "--allow").includes(target), !split, target);
          assert.equal(paths(args, "--read").includes(target), split, target);
        }
      }
      if (linux && name === "dotfiles" && nested) assert.ok(paths(args, "--allow").includes(cwd));
    });
  }
}

test("similarly named project directories cannot activate the write exception", () => {
  const f = fixture();
  for (const name of ["dotfiles-copy", "nixos-copy"]) {
    const cwd = join(f.home, name);
    mkdirSync(cwd);
    assertReadOnly(f.args(cwd), [f.dotfiles, f.nixos, f.vault]);
  }
});

test("reference names and writable metadata cannot manufacture a write exception", () => {
  const f = fixture();
  const arbitrary = join(f.root, "nixos");
  mkdirSync(arbitrary);
  f.approve(arbitrary, f.vault);
  mkdirSync(join(f.dotfiles, ".pi"));
  writeFileSync(join(f.dotfiles, ".pi", "settings.json"), JSON.stringify({ references: {
    nixos: { path: arbitrary, description: "Override", access: "readwrite", write: true },
    vault: { path: f.vault, description: "Vault", access: "readwrite", write: true },
  } }));
  writeFileSync(join(f.agent, "trust.json"), JSON.stringify({ [f.dotfiles]: true }));
  assertReadOnly(f.args(f.dotfiles), [arbitrary, f.vault]);
});

test("paired repository descendants are writable while sibling references stay read-only", () => {
  const f = fixture();
  const child = join(f.nixos, "modules");
  const sibling = join(f.home, "nixos-other");
  mkdirSync(child);
  mkdirSync(sibling);
  f.approve(sibling);
  writeFileSync(f.settings, JSON.stringify({ references: {
    child: { path: child, description: "Modules" },
    sibling: { path: sibling, description: "Sibling" },
  } }));
  const args = f.args(f.dotfiles);
  assert.ok(paths(args, "--allow").includes(child));
  assertReadOnly(args, [sibling]);
});

test("home ancestor references need host approval and then fail on the GitHub credential store", t => {
  const f = fixture();
  writeFileSync(f.settings, JSON.stringify({ references: {
    home: { path: f.home, description: "Home" },
  } }));
  const warning = t.mock.method(console, "warn", () => {});
  assert.ok(!paths(f.args(f.dotfiles), "--read").includes(f.home));
  assert.ok(warning.mock.calls.some(call => /unapproved reference "home"/.test(call.arguments[0])));
  f.approve(f.home);
  assert.throws(() => f.args(f.dotfiles), /GitHub credential store overlaps a Pi sandbox grant/);
});

test("canonical paths determine the exception rather than symlink names", () => {
  const f = fixture();
  const alias = join(f.root, "work-alias");
  const escaped = join(f.dotfiles, "escaped");
  symlinkSync(f.dotfiles, alias);
  symlinkSync(f.vault, escaped);
  writeFileSync(f.settings, JSON.stringify({ references: {
    nixos: { path: f.nixos, description: "NixOS" },
    escaped: { path: escaped, description: "External symlink" },
  } }));
  const args = f.args(alias);
  assert.ok(paths(args, "--allow").includes(f.nixos));
  assertReadOnly(args, [f.vault]);
});

test("missing paired repositories do not prevent unrelated launches", () => {
  const f = fixture();
  rmSync(f.dotfiles, { recursive: true });
  rmSync(f.nixos, { recursive: true });
  assertReadOnly(f.args(), [f.vault]);
});

test("nonexistent homes do not prevent unrelated launches", t => {
  const f = fixture();
  t.mock.method(console, "warn", () => {});
  const args = launchArguments(f.project, f.agent, join(f.root, "missing-home"), { TMPDIR: f.temporary, XDG_RUNTIME_DIR: f.runtime }, profile, process.execPath, envBinary);
  // A missing home has no host approval store, so the external vault stays ungranted.
  for (const flag of ["--read", "--allow"]) assert.ok(!paths(args, flag).includes(f.vault), flag);
});

test("paired repository symlinks cannot expand writes to home or its ancestors", () => {
  const f = fixture();
  rmSync(f.dotfiles, { recursive: true });
  for (const target of [f.home, f.root, "/"]) {
    symlinkSync(target, f.dotfiles);
    assert.throws(() => f.args(), /must not resolve to the home directory or an ancestor/);
    rmSync(f.dotfiles);
  }
});

test("docs-cache symlinks to outside directories receive only read grants", () => {
  const f = fixture();
  mkdirSync(join(f.dotfiles, ".docs"));
  symlinkSync(f.vault, join(f.dotfiles, ".docs", "api"));
  writeFileSync(join(f.dotfiles, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  assertReadOnly(f.args(f.dotfiles), [f.vault]);
});

test("unapproved settings and docs-cache references add no grants and name the host approval store", t => {
  const f = fixture();
  const store = f.approve();
  const warning = t.mock.method(console, "warn", () => {});
  mkdirSync(join(f.dotfiles, ".docs"));
  symlinkSync(f.vault, join(f.dotfiles, ".docs", "api"));
  writeFileSync(join(f.dotfiles, "docs-lock.json"), JSON.stringify({ version: 1, sources: { api: { repo: "owner/api" } } }));
  for (const cwd of [f.project, f.dotfiles]) {
    const args = f.args(cwd);
    for (const flag of ["--read", "--allow"]) assert.ok(!paths(args, flag).includes(f.vault), `${cwd} ${flag}`);
  }
  const skipped = warning.mock.calls.map(call => call.arguments[0]).filter(message => /unapproved reference/.test(message));
  // The vault reference is skipped from both directories and the docs symlink from dotfiles.
  assert.equal(skipped.length, 3);
  for (const message of skipped) assert.ok(message.includes(store), message);
});

test("reference approvals must be a private host file listing absolute paths", () => {
  const f = fixture();
  const store = referenceApprovalStore(f.home);
  chmodSync(store, 0o666);
  assert.throws(() => f.args(), /Reference approvals must be a user-owned regular file/);
  chmodSync(store, 0o600);
  writeFileSync(store, JSON.stringify(["relative/path"]));
  assert.throws(() => f.args(), /JSON array of absolute paths/);
  rmSync(store);
  symlinkSync(f.settings, store);
  assert.throws(() => f.args(), /Reference approvals must be a user-owned regular file/);
});

test("writable launcher grants cannot reach the reference approval store", () => {
  const f = fixture();
  assert.throws(() => f.args(f.project, { PI_HASHLINE_DIR: join(f.home, ".local", "state") }), /host-only path/);
});

test("explicit Pi state grants remain writable despite overlapping references", () => {
  const f = fixture();
  const cache = join(f.home, ".cache", "pi");
  mkdirSync(cache, { recursive: true });
  writeFileSync(f.settings, JSON.stringify({ references: {
    agent: { path: f.agent, description: "Agent state" },
    cache: { path: cache, description: "Cache" },
  } }));
  const args = f.args();
  assert.ok(paths(args, "--allow").includes(f.agent));
  assert.ok(paths(args, "--allow").includes(cache));
});

function shellFixture() {
  const f = fixture(process.cwd());
  const fish = join(f.dotfiles, ".config", "fish");
  const nvim = join(f.dotfiles, ".config", "nvim");
  const readme = join(f.dotfiles, "README.md");
  const link = join(f.home, ".config", "fish", "config.fish");
  for (const path of [fish, nvim, join(f.dotfiles, ".pi"), dirname(link)]) mkdirSync(path, { recursive: true });
  writeFileSync(join(fish, "config.fish"), "# fixture\n");
  writeFileSync(join(nvim, "init.lua"), "-- fixture\n");
  writeFileSync(readme, "fixture\n");
  // Mirrors the stow layout that let a sandboxed write reach the host shell configuration.
  symlinkSync(join(fish, "config.fish"), link);
  return { ...f, fish, nvim, readme, link };
}

test("Linux grants dotfiles entries around shell startup files instead of the repository root", { skip: !linux }, () => {
  const f = shellFixture();
  for (const cwd of [f.nixos, f.dotfiles]) {
    const args = f.args(cwd);
    const writable = [...paths(args, "--allow"), ...paths(args, "--allow-file")];
    for (const path of writable) {
      assert.ok(path !== f.dotfiles && path !== join(f.dotfiles, ".config") && path !== f.fish && !path.startsWith(`${f.fish}/`), `${cwd}: ${path}`);
    }
    for (const path of [f.dotfiles, join(f.dotfiles, ".config")]) assert.ok(paths(args, "--read").includes(path), `${cwd}: ${path}`);
    for (const path of [f.nvim, join(f.dotfiles, ".pi")]) assert.ok(paths(args, "--allow").includes(path), `${cwd}: ${path}`);
    assert.ok(paths(args, "--allow-file").includes(f.readme), cwd);
    assert.equal(args.includes("--allow-cwd"), cwd !== f.dotfiles, cwd);
  }
});

test("Linux denies shell startup writes through stow links while dotfiles contents stay writable", {
  skip: !linux || !process.env.NONO_TEST_BINARY,
}, () => {
  const f = shellFixture();
  const environment = liveEnvironment(f);
  const probe = `
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const [link, fish, nvim, readme, dotfiles] = process.argv.slice(1);
    const denied = { code: "EACCES" };
    assert.equal(fs.readFileSync(path.join(fish, "config.fish"), "utf8"), "# fixture\\n");
    assert.throws(() => fs.appendFileSync(link, "changed"), denied);
    assert.throws(() => fs.appendFileSync(path.join(fish, "config.fish"), "changed"), denied);
    assert.throws(() => fs.mkdirSync(path.join(fish, "conf.d")), denied);
    assert.throws(() => fs.mkdirSync(path.join(dotfiles, ".config", "newapp")), denied);
    assert.throws(() => fs.writeFileSync(path.join(dotfiles, "new-top-level"), "new"), denied);
    fs.writeFileSync(path.join(nvim, "init.lua"), "-- changed\\n");
    fs.appendFileSync(readme, "changed\\n");
  `;
  for (const cwd of [f.nixos, f.dotfiles]) {
    const child = spawnSync(process.env.NONO_TEST_BINARY, [
      ...withoutWorkdirGrant(f, f.args(cwd, environment)), "-e", probe, f.link, f.fish, f.nvim, f.readme, f.dotfiles,
    ], { cwd, env: environment, encoding: "utf8", timeout: 30000 });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
    assert.equal(readFileSync(join(f.fish, "config.fish"), "utf8"), "# fixture\n");
  }
});

test("Linux enforces external reference reads and ordinary paired repository writes", {
  skip: !linux || !process.env.NONO_TEST_BINARY,
}, () => {
  // /tmp is writable in nono's default profile, so keep denied-write fixtures in the checkout.
  const f = fixture(process.cwd());
  mkdirSync(join(f.dotfiles, "existing"));
  const environment = liveEnvironment(f);
  const probe = `
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const [cwd, dotfiles, nixos, vault, paired, split] = process.argv.slice(1);
    for (const directory of new Set([cwd, dotfiles, nixos, vault])) {
      const original = path.join(directory, "original");
      assert.equal(fs.readFileSync(original, "utf8"), "unchanged");
      assert.ok(fs.readdirSync(directory).includes("original"));
      const writable = directory === cwd || (paired === "yes" && directory !== vault);
      // A split root keeps its own entries fixed while existing files and subdirectories stay writable.
      if (!writable || directory === split) {
        for (const operation of [
          ...(writable ? [] : [() => fs.writeFileSync(original, "changed"), () => fs.appendFileSync(original, "changed")]),
          () => fs.writeFileSync(path.join(directory, "new"), "new"),
          () => fs.mkdirSync(path.join(directory, "new-directory")),
          () => fs.renameSync(original, path.join(directory, "renamed")),
          () => fs.unlinkSync(original),
        ]) assert.throws(operation, { code: "EACCES" });
        if (!writable) continue;
        fs.appendFileSync(original, "");
      }
      const nested = path.join(directory === split ? path.join(directory, "existing") : directory, "new-directory");
      fs.mkdirSync(nested);
      const target = path.join(nested, "file");
      const replacement = path.join(nested, "temporary");
      fs.writeFileSync(target, "old");
      fs.writeFileSync(replacement, "new");
      fs.renameSync(replacement, target);
      assert.equal(fs.readFileSync(target, "utf8"), "new");
      fs.unlinkSync(target);
      fs.rmdirSync(nested);
    }
  `;
  for (const cwd of [f.project, f.dotfiles, f.nixos]) {
    for (const directory of [f.project, f.dotfiles, f.nixos, f.vault]) writeFileSync(join(directory, "original"), "unchanged");
    const paired = cwd !== f.project;
    const child = spawnSync(process.env.NONO_TEST_BINARY, [
      ...withoutWorkdirGrant(f, f.args(cwd, environment)), "-e", probe, cwd, f.dotfiles, f.nixos, f.vault, paired ? "yes" : "no", f.dotfiles,
    ], { cwd, env: environment, encoding: "utf8", timeout: 30000 });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
  }
});
