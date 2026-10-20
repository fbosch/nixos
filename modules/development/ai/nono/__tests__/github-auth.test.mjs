import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { direnvGithubEnvironment, prepareGithubEnvironment } from "../scripts/github-auth.mjs";

const token = "synthetic-github-credential";
const aliases = ["GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"];

for (const name of aliases) {
  test(`inherited ${name} is withheld from direnv and fails closed before nono`, () => {
    const inherited = { [name]: token, PATH: "/trusted" };
    assert.equal(direnvGithubEnvironment(inherited)[name], undefined);
    assert.throws(() => prepareGithubEnvironment(inherited, {}, "/home/user"), /GitHub token environment variables/);
  });
  test(`project ${name} cannot become a supervisor or child credential`, () => {
    assert.throws(() => prepareGithubEnvironment({}, { [name]: token }, "/home/user"), /GitHub token environment variables/);
  });
}

test("host capture location is not selected by the project; unrelated environment survives", () => {
  const loaded = { PATH: "/project/bin", GH_CONFIG_DIR: "/project/gh", GH_HOST: "elsewhere", GITHUB_HOST: "elsewhere", NONO_ALLOW_NET: "1", OTHER: "preserved" };
  assert.deepEqual(prepareGithubEnvironment({}, loaded, "/home/user"), {
    PATH: "/project/bin", GH_CONFIG_DIR: "/home/user/.config/gh", OTHER: "preserved",
  });
});

test("launcher rejects project token without passing it to direnv, nono or argv", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-github-bootstrap-"));
  try {
    const home = join(root, "home");
    const agent = join(home, ".pi", "agent");
    const cwd = join(root, "project");
    mkdirSync(agent, { recursive: true });
    mkdirSync(cwd);
    writeFileSync(join(cwd, ".envrc"), "fixture");
    const direnv = join(root, "direnv");
    const nono = join(root, "nono");
    writeFileSync(direnv, `#!${process.execPath}\nimport assert from 'node:assert/strict';assert.equal(process.env.GH_TOKEN,undefined);console.log(JSON.stringify({GH_TOKEN:'${token}'}));\n`, { mode: 0o700 });
    writeFileSync(nono, `#!${process.execPath}\nthrow new Error('nono must not run');\n`, { mode: 0o700 });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
    const result = spawnSync(process.execPath, [launcher, nono, process.execPath, profile, direnv, "--version"], {
      cwd, env: { HOME: home, PATH: process.env.PATH, TMPDIR: root, PI_CODING_AGENT_DIR: agent, GH_TOKEN: token },
      encoding: "utf8", timeout: 15_000,
    });
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /GitHub token environment variables/);
    assert.ok(!result.stderr.includes(token));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});


test("missing GitHub login does not block unrelated Pi startup or expose supervisor aliases", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-github-no-login-"));
  try {
    const home = join(root, "home");
    const agent = join(home, ".pi", "agent");
    const cwd = join(root, "project");
    mkdirSync(agent, { recursive: true });
    mkdirSync(cwd);
    const runtime = join(root, "runtime");
    mkdirSync(runtime);
    const nono = join(root, "nono");
    writeFileSync(nono, `#!${process.execPath}\nimport assert from 'node:assert/strict';for (const name of ${JSON.stringify(aliases)}) assert.equal(process.env[name],undefined);assert.equal(process.env.NONO_ALLOW_NET,undefined);assert.ok(process.argv.includes('--profile'));console.log('started without login');\n`, { mode: 0o700 });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
    const child = spawnSync(process.execPath, [launcher, nono, process.execPath, profile, "/missing-direnv", "--version"], {
      cwd, env: { HOME: home, PATH: process.env.PATH, TMPDIR: runtime, XDG_RUNTIME_DIR: runtime, PI_CODING_AGENT_DIR: agent, NONO_ALLOW_NET: "1" },
      encoding: "utf8", timeout: 15000,
    });
    assert.equal(child.status, 0, child.stderr);
    assert.equal(child.stdout.trim(), "started without login");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("file, socket, bypass, and ancestor grants cannot alias a symlinked hosts credential", async () => {
  const { assertGithubCredentialGrants } = await import("../scripts/github-auth.mjs");
  const root = mkdtempSync(join(tmpdir(), "pi-github-grants-"));
  try {
    const home = join(root, "home");
    const store = join(home, ".config", "gh");
    const targetRoot = join(root, "target");
    const safe = join(root, "safe");
    mkdirSync(store, { recursive: true });
    mkdirSync(targetRoot);
    mkdirSync(safe);
    const target = join(targetRoot, "token");
    writeFileSync(target, "synthetic");
    const { symlinkSync, linkSync } = await import("node:fs");
    symlinkSync(target, join(store, "hosts.yml"));
    for (const flag of ["--allow", "--read", "--allow-file", "--read-file", "--allow-unix-socket", "--bypass-protection"]) {
      assert.throws(() => assertGithubCredentialGrants(["run", flag, target, "--", "pi"], safe, home), /GitHub credential/);
      assert.throws(() => assertGithubCredentialGrants(["run", flag, targetRoot, "--", "pi"], safe, home), /GitHub credential/);
    }
    assert.doesNotThrow(() => assertGithubCredentialGrants(["run", "--allow", safe, "--", "pi", "--read", store], safe, home));
    rmSync(join(store, "hosts.yml"));
    linkSync(target, join(store, "hosts.yml"));
    assert.throws(() => assertGithubCredentialGrants(["run", "--allow", safe, "--", "pi"], safe, home), /hard links/);
    rmSync(join(store, "hosts.yml"));
    symlinkSync(join(root, "missing"), join(store, "hosts.yml"));
    assert.throws(() => assertGithubCredentialGrants(["run", "--allow", safe, "--", "pi"], safe, home), /Cannot resolve GitHub credential/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});


test("declared profile paths cannot expose credentials through TMPDIR or a broad read", async () => {
  const { assertGithubCredentialGrants } = await import("../scripts/github-auth.mjs");
  const root = mkdtempSync(join(tmpdir(), "pi-github-static-"));
  try {
    const home = join(root, "home");
    const safe = join(root, "safe");
    const store = join(home, ".config", "gh");
    mkdirSync(store, { recursive: true });
    mkdirSync(safe);
    const profile = { filesystem: { read: ["$TMPDIR"] } };
    assert.throws(() => assertGithubCredentialGrants([], safe, home, { TMPDIR: root }, profile), /GitHub credential/);
    assert.throws(() => assertGithubCredentialGrants([], safe, home, {}, { filesystem: { read: [home] } }), /GitHub credential/);
    assert.doesNotThrow(() => assertGithubCredentialGrants([], safe, home, { TMPDIR: safe }, profile));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
