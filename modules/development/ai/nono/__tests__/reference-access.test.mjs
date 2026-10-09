import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { launchArguments } from "../scripts/launcher.mjs";

const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const created = [];

function fixture(base = tmpdir()) {
  const root = realpathSync(mkdtempSync(join(base, ".pi-reference-test-")));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const project = join(home, "project");
  const dotfiles = join(home, "dotfiles");
  const nixos = join(home, "nixos");
  const vault = join(root, "vault");
  for (const path of [agent, project, dotfiles, nixos, vault]) mkdirSync(path, { recursive: true });
  const settings = join(agent, "settings.json");
  writeFileSync(settings, JSON.stringify({ references: {
    dotfiles: { path: "~/dotfiles", description: "Dotfiles" },
    nixos: { path: "~/nixos", description: "NixOS" },
    vault: { path: vault, description: "Vault" },
  } }));
  const args = (cwd = project, environment = {}) => launchArguments(cwd, agent, home, environment, profile, process.execPath);
  return { root, home, agent, project, dotfiles, nixos, vault, settings, args };
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
        if (target === cwd) {
          assert.ok(args.includes("--allow-cwd"));
          assert.ok(!paths(args, "--read").includes(target));
        } else {
          assert.ok(paths(args, "--allow").includes(target), target);
          assert.ok(!paths(args, "--read").includes(target), target);
        }
      }
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
  mkdirSync(join(f.dotfiles, ".pi"));
  writeFileSync(join(f.dotfiles, ".pi", "settings.json"), JSON.stringify({ references: {
    nixos: { path: arbitrary, description: "Override", access: "readwrite", write: true },
    vault: { path: f.vault, description: "Vault", access: "readwrite", write: true },
  } }));
  writeFileSync(join(f.agent, "trust.json"), JSON.stringify({ [f.dotfiles]: true }));
  assertReadOnly(f.args(f.dotfiles), [arbitrary, f.vault]);
});

test("paired repository descendants are writable but ancestor and sibling references are not", () => {
  const f = fixture();
  const child = join(f.nixos, "modules");
  const sibling = join(f.home, "nixos-other");
  mkdirSync(child);
  mkdirSync(sibling);
  writeFileSync(f.settings, JSON.stringify({ references: {
    child: { path: child, description: "Modules" },
    parent: { path: f.home, description: "Home" },
    sibling: { path: sibling, description: "Sibling" },
  } }));
  const args = f.args(f.dotfiles);
  assert.ok(paths(args, "--allow").includes(child));
  assertReadOnly(args, [f.home, sibling]);
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

test("nonexistent homes do not prevent unrelated launches", () => {
  const f = fixture();
  const args = launchArguments(f.project, f.agent, join(f.root, "missing-home"), {}, profile, process.execPath);
  assertReadOnly(args, [f.vault]);
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

test("Linux enforces external reference reads and ordinary paired repository writes", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
}, () => {
  // /tmp is writable in nono's default profile, so keep denied-write fixtures in the checkout.
  const f = fixture(process.cwd());
  const temporary = join(f.root, "tmp");
  mkdirSync(temporary);
  const environment = {
    ...process.env,
    HOME: f.home,
    PI_CODING_AGENT_DIR: f.agent,
    XDG_CONFIG_HOME: join(f.home, ".config"),
    XDG_DATA_HOME: join(f.home, ".local", "share"),
    XDG_CACHE_HOME: join(f.home, ".cache"),
    XDG_STATE_HOME: join(f.root, "state"),
    TMPDIR: temporary,
    PI_HASHLINE_DIR: join(f.home, ".config", "pi-hashline-edit-pro"),
    FFF_FRECENCY_DB: join(f.home, ".cache", "fff"),
    FFF_HISTORY_DB: join(f.home, ".local", "share", "fff"),
  };
  const probe = `
    const assert = require("node:assert/strict");
    const fs = require("node:fs");
    const path = require("node:path");
    const [cwd, dotfiles, nixos, vault, paired] = process.argv.slice(1);
    for (const directory of new Set([cwd, dotfiles, nixos, vault])) {
      const original = path.join(directory, "original");
      assert.equal(fs.readFileSync(original, "utf8"), "unchanged");
      assert.ok(fs.readdirSync(directory).includes("original"));
      const writable = directory === cwd || (paired === "yes" && directory !== vault);
      if (!writable) {
        for (const operation of [
          () => fs.writeFileSync(original, "changed"),
          () => fs.appendFileSync(original, "changed"),
          () => fs.writeFileSync(path.join(directory, "new"), "new"),
          () => fs.mkdirSync(path.join(directory, "new-directory")),
          () => fs.renameSync(original, path.join(directory, "renamed")),
          () => fs.unlinkSync(original),
        ]) assert.throws(operation, { code: "EACCES" });
        continue;
      }
      const nested = path.join(directory, "new-directory");
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
      ...f.args(cwd, environment), "-e", probe, cwd, f.dotfiles, f.nixos, f.vault, paired ? "yes" : "no",
    ], { cwd, env: environment, encoding: "utf8", timeout: 30000 });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
  }
});
