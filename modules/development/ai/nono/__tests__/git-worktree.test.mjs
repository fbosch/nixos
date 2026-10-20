import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { join, relative } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { launchArguments } from "../scripts/launcher.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const created = [];

// Keep fixture HOME outside the shared temporary-directory read grants.
function fixture(base = process.cwd()) {
  const root = realpathSync(mkdtempSync(join(base, ".pi-worktree-test-")));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const project = join(root, "KommuneKredit.Frontend");
  const cwd = join(project, "refactor-modernize-agentic-skills");
  const common = join(project, ".bare");
  const gitDir = join(common, "worktrees", "refactor-modernize-agentic-skills");
  const temporary = join(root, "tmp");
  const runtime = join(root, "runtime");
  for (const directory of [agent, cwd, gitDir, temporary, runtime]) mkdirSync(directory, { recursive: true });
  for (const name of ["objects", "refs"]) mkdirSync(join(common, name));
  writeFileSync(join(common, "HEAD"), "ref: refs/heads/main\n");
  writeFileSync(join(cwd, ".git"), `gitdir: ${gitDir}\n`);
  writeFileSync(join(gitDir, "commondir"), "../..\n");
  writeFileSync(join(gitDir, "gitdir"), `${join(cwd, ".git")}\n`);
  const args = (directory = cwd) => launchArguments(directory, agent, home, { TMPDIR: temporary, XDG_RUNTIME_DIR: runtime }, profile, process.execPath, envBinary);
  return { root, home, agent, project, cwd, common, gitDir, args };
}

afterEach(() => {
  for (const directory of created.splice(0)) rmSync(directory, { recursive: true, force: true });
});

function paths(args, flag) {
  return args.flatMap((value, index) => value === flag ? [args[index + 1]] : []);
}

test("bare worktrees grant shared Git metadata without granting the parent or sibling checkouts", () => {
  const f = fixture();
  const args = f.args();
  assert.ok(paths(args, "--allow").includes(f.common), "the external .bare metadata must be writable");
  assert.ok(!paths(args, "--allow").includes(f.project));
  assert.ok(!paths(args, "--read").includes(f.project));
});

test("resolves relative .git, commondir and backlink paths from a nested worktree directory", () => {
  const f = fixture();
  const nested = join(f.cwd, "src", "nested");
  mkdirSync(nested, { recursive: true });
  writeFileSync(join(f.cwd, ".git"), `gitdir: ${relative(f.cwd, f.gitDir)}\r\n`);
  writeFileSync(join(f.gitDir, "gitdir"), `${relative(f.gitDir, join(f.cwd, ".git"))}\r\n`);
  assert.ok(paths(f.args(nested), "--allow").includes(f.common));
  assert.ok(!paths(f.args(nested), "--allow").includes(f.cwd));
});

test("canonicalizes metadata aliases without assuming a .bare name and preserves Danish paths", () => {
  const f = fixture();
  const common = join(f.project, "metadata æøå with spaces");
  renameSync(f.common, common);
  symlinkSync(common, f.common);
  assert.ok(paths(f.args(), "--allow").includes(common));
  assert.ok(!paths(f.args(), "--allow").includes(f.common));
});

test("ordinary .git directories remain inside cwd grants and nested repositories stop discovery", () => {
  const f = fixture();
  rmSync(join(f.cwd, ".git"));
  mkdirSync(join(f.cwd, ".git"));
  assert.ok(!paths(f.args(), "--allow").includes(f.common));
  assert.ok(!paths(f.args(), "--allow").includes(join(f.cwd, ".git")));
  const nested = join(f.cwd, "nested");
  mkdirSync(join(nested, ".git"), { recursive: true });
  assert.ok(!paths(f.args(nested), "--allow").includes(join(f.cwd, ".git")));
});

test("ordinary repository subdirectories receive only the ancestor's .git metadata", () => {
  const f = fixture();
  rmSync(join(f.cwd, ".git"));
  mkdirSync(join(f.cwd, ".git"));
  const nested = join(f.cwd, "src");
  mkdirSync(nested);
  assert.ok(paths(f.args(nested), "--allow").includes(join(f.cwd, ".git")));
  assert.ok(!paths(f.args(nested), "--allow").includes(f.cwd));
});

test("rejects malformed pointers and reports missing metadata without silently dropping grants", () => {
  const f = fixture();
  for (const pointer of ["not a git pointer", "gitdir: \n", `gitdir: ${f.gitDir}\nextra\n`]) {
    writeFileSync(join(f.cwd, ".git"), pointer);
    assert.throws(() => f.args(), /Cannot resolve Git metadata.*Invalid .git worktree pointer/);
  }
  writeFileSync(join(f.cwd, ".git"), `gitdir: ${join(f.root, "missing")}\n`);
  assert.throws(() => f.args(), /Cannot resolve Git metadata.*ENOENT/);
});

test("reports inaccessible metadata as an access error rather than missing metadata", { skip: process.getuid?.() === 0 }, () => {
  const f = fixture();
  chmodSync(f.common, 0o000);
  try {
    assert.throws(() => f.args(), /Cannot resolve Git metadata.*(?:EACCES|EPERM)/);
  } finally {
    chmodSync(f.common, 0o700);
  }
});

test("rejects a pointer to another checkout's registered metadata", () => {
  const f = fixture();
  const other = join(f.project, "other");
  mkdirSync(other);
  writeFileSync(join(other, ".git"), `gitdir: ${f.gitDir}\n`);
  writeFileSync(join(f.gitDir, "gitdir"), `${join(other, ".git")}\n`);
  assert.throws(() => f.args(), /registration does not match this checkout/);
});

test("rejects redirected commondir paths and symlinked .git markers", () => {
  const f = fixture();
  writeFileSync(join(f.gitDir, "commondir"), `${f.home}\n`);
  assert.throws(() => f.args(), /registration does not match this checkout/);
  rmSync(join(f.cwd, ".git"));
  symlinkSync(f.common, join(f.cwd, ".git"));
  assert.throws(() => f.args(), /regular worktree pointer file/);
});

for (const target of ["home", "project"]) {
  test(`rejects even registered metadata that would grant the ${target} directory`, () => {
    const f = fixture();
    const common = f[target];
    const gitDir = join(common, "worktrees", "fixture");
    for (const directory of [gitDir, join(common, "objects"), join(common, "refs")]) mkdirSync(directory, { recursive: true });
    writeFileSync(join(common, "HEAD"), "ref: refs/heads/main\n");
    writeFileSync(join(f.cwd, ".git"), `gitdir: ${gitDir}\n`);
    writeFileSync(join(gitDir, "commondir"), "../..\n");
    writeFileSync(join(gitDir, "gitdir"), `${join(f.cwd, ".git")}\n`);
    assert.throws(() => f.args(), /home directory or a checkout ancestor/);
  });
}

function git(args, cwd, environment) {
  const child = spawnSync(process.env.GIT_TEST_BINARY || "git", args, {
    cwd, env: environment, encoding: "utf8", timeout: 10000,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  return child.stdout.trim();
}

function gitFixture(bare, base = process.cwd()) {
  const f = fixture(base);
  rmSync(f.project, { recursive: true });
  mkdirSync(f.project);
  const main = join(f.project, "main");
  const common = bare ? f.common : join(main, ".git");
  const environment = {
    ...process.env,
    HOME: f.home,
    XDG_CONFIG_HOME: join(f.home, ".config"),
    XDG_DATA_HOME: join(f.home, ".local", "share"),
    XDG_CACHE_HOME: join(f.home, ".cache"),
    XDG_STATE_HOME: join(f.root, "state"),
    TMPDIR: join(f.root, "tmp"),
  };
  for (const name of Object.keys(environment)) if (name.startsWith("GIT_")) delete environment[name];
  environment.GIT_CONFIG_NOSYSTEM = "1";
  environment.GIT_CONFIG_GLOBAL = "/dev/null";
  for (const name of ["XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME", "XDG_STATE_HOME", "TMPDIR"]) {
    mkdirSync(environment[name], { recursive: true });
  }
  git(["init", "--initial-branch=main", ...(bare ? ["--bare", common] : [main])], f.project, environment);
  git(["--git-dir", common, "worktree", "add", "--orphan", "-b", "feature", f.cwd], f.project, environment);
  return { ...f, common, environment };
}

for (const bare of [true, false]) {
  test(`resolves real Git-created ${bare ? "bare" : "non-bare"} worktree registration`, () => {
    const f = gitFixture(bare);
    assert.equal(git(["rev-parse", "--show-toplevel"], f.cwd, f.environment), f.cwd);
    assert.ok(paths(f.args(), "--allow").includes(f.common));
  });
}

test("wt list recognizes the real bare-worktree fixture", { skip: !process.env.WT_TEST_BINARY }, () => {
  const f = gitFixture(true);
  const child = spawnSync(process.env.WT_TEST_BINARY, ["list", "--format=json", "--no-progressive"], {
    cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 10000,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.ok(child.stdout.includes(f.cwd));
});

test("Nono resolves the scoped shared-metadata grant", {
  skip: !process.env.NONO_TEST_BINARY,
}, () => {
  const f = gitFixture(true, process.cwd());
  const args = launchArguments(f.cwd, f.agent, f.home, f.environment, profile, process.execPath, envBinary);
  args.splice(args.indexOf("--"), 0, "--dry-run");
  const child = spawnSync(process.env.NONO_TEST_BINARY, args, {
    cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 30000,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.ok(`${child.stdout}${child.stderr}`.includes(f.common));
});

test("Nono permits Git metadata reads and writes while denying sibling checkout access", {
  skip: !process.env.NONO_TEST_BINARY,
}, () => {
  // Default temporary-directory grants would mask missing grants and sibling access denials.
  const f = gitFixture(true, process.cwd());
  const sibling = join(f.project, "other-worktree");
  mkdirSync(sibling);
  writeFileSync(join(sibling, "private.txt"), "unchanged");
  const probe = fileURLToPath(new URL("./fixtures/git-worktree-probe.mjs", import.meta.url));
  const args = launchArguments(f.cwd, f.agent, f.home, f.environment, profile, process.execPath, envBinary);
  args.splice(args.indexOf("--"), 0, "--read-file", probe);
  const child = spawnSync(process.env.NONO_TEST_BINARY, [
    ...args,
    probe, f.cwd, f.common, sibling, process.env.GIT_TEST_BINARY || "git", process.env.WT_TEST_BINARY || "",
  ], { cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 30000 });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.equal(readFileSync(join(f.cwd, "note.txt"), "utf8"), "worktree fixture\n");
  assert.equal(readFileSync(join(sibling, "private.txt"), "utf8"), "unchanged");
});
