import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { loadGithubEnvironment } from "../scripts/github-auth.mjs";

const gh = "/packaged/bin/gh";
const token = "synthetic-github-credential";

for (const platform of ["darwin", "linux"]) {
  test(`${platform}: captures only a GitHub token using packaged gh and the inherited credential environment`, () => {
    const environment = { PATH: "/project/bin", GH_CONFIG_DIR: "/project/config", OTHER: "preserved" };
    const inherited = { PATH: "/trusted/bin", GH_CONFIG_DIR: "/trusted/config", GH_DEBUG: "api", DEBUG: "1", BASH_ENV: "/untrusted", ENV: "/untrusted", NODE_OPTIONS: "--require untrusted", NODE_PATH: "/untrusted" };
    const loaded = loadGithubEnvironment(environment, gh, {
      platform,
      credentialEnvironment: inherited,
      run(binary, args, options) {
        assert.equal(binary, gh);
        assert.deepEqual(args, ["auth", "token", "--hostname", "github.com"]);
        assert.equal(options.cwd, "/");
        assert.deepEqual(options.env, { PATH: "/trusted/bin", GH_CONFIG_DIR: "/trusted/config" });
        assert.deepEqual(options.stdio, ["ignore", "pipe", "ignore"]);
        assert.equal(options.timeout, 10_000);
        return { status: 0, stdout: `${token}\n` };
      },
      warn() { assert.fail("successful retrieval must not warn"); },
    });
    assert.deepEqual(loaded, { ...environment, GH_TOKEN: token });
    assert.equal(environment.GH_TOKEN, undefined);
    assert.equal(inherited.GH_DEBUG, "api");
  });

  for (const name of ["GH_TOKEN", "GITHUB_TOKEN"]) {
    test(`${platform}: preserves explicit ${name} without querying the credential store`, () => {
      const environment = { [name]: token };
      assert.deepEqual(loadGithubEnvironment(environment, gh, {
        platform, run() { assert.fail("must not query the credential store"); },
      }), environment);
    });
  }

  test(`${platform}: rejects a PATH-selected credential executable`, () => {
    assert.throws(() => loadGithubEnvironment({}, "gh", { platform }), /must be absolute/);
  });

  for (const result of [
    { status: 1, stdout: token, stderr: token },
    { status: 0, stdout: "" },
    { status: 0, stdout: "first\nsecond" },
    { status: 0, stdout: "credential\u0000" },
    { status: null, error: new Error(token), stdout: token },
  ]) {
    test(`${platform}: failed credential retrieval warns without disclosing subprocess output or errors`, () => {
      const warnings = [];
      assert.deepEqual(loadGithubEnvironment({}, gh, {
        platform, run() { return result; }, warn(message) { warnings.push(message); },
      }), {});
      assert.equal(warnings.length, 1);
      assert.match(warnings[0], /GitHub credential unavailable/);
      assert.ok(!warnings[0].includes(token));
    });
  }
}

test("launcher passes the captured token to nono but not project direnv or command arguments", {
  skip: !["darwin", "linux"].includes(process.platform),
}, () => {
  const root = mkdtempSync(join(tmpdir(), "pi-github-bootstrap-"));
  try {
    const home = join(root, "home");
    const agent = join(home, ".pi", "agent");
    const cwd = join(root, "project");
    mkdirSync(agent, { recursive: true, mode: 0o700 });
    mkdirSync(cwd);
    writeFileSync(join(cwd, ".envrc"), "fixture");
    const cli = join(root, "gh");
    const direnv = join(root, "direnv");
    const nono = join(root, "nono");
    writeFileSync(cli, `#!${process.execPath}\nimport assert from 'node:assert/strict';assert.deepEqual(process.argv.slice(2),['auth','token','--hostname','github.com']);assert.equal(process.env.GH_CONFIG_DIR,'/trusted/config');assert.equal(process.env.GH_DEBUG,undefined);console.log('${token}');\n`, { mode: 0o700 });
    writeFileSync(direnv, `#!${process.execPath}\nimport assert from 'node:assert/strict';assert.equal(process.env.GH_TOKEN,undefined);console.log(JSON.stringify({PATH:'/project/bin',GH_CONFIG_DIR:'/project/config'}));\n`, { mode: 0o700 });
    writeFileSync(nono, `#!${process.execPath}\nimport assert from 'node:assert/strict';assert.equal(process.env.GH_TOKEN,'${token}');assert.ok(!process.argv.join(' ').includes('${token}'));console.log('authenticated fixture');\n`, { mode: 0o700 });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
    const result = spawnSync(process.execPath, [launcher, nono, process.execPath, profile, direnv, cli, "--version"], {
      cwd,
      env: { PATH: process.env.PATH, HOME: home, TMPDIR: root, PI_CODING_AGENT_DIR: agent, GH_CONFIG_DIR: "/trusted/config", GH_DEBUG: "api" },
      encoding: "utf8",
      timeout: 15_000,
    });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout.trim(), "authenticated fixture");
    assert.ok(!result.stderr.includes(token));
    assert.ok(!result.stdout.includes(token));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
