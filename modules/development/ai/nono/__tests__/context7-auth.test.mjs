import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { linkSync, mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { assertCredentialSourceGrants, credentialDefinitions, credentialEnvironmentForDirenv, prepareCredentialEnvironment } from "../scripts/credentials.mjs";

const context7 = { context7: credentialDefinitions.context7 };
const context7SecretPath = context7.context7.source.path;
const direnvContext7Environment = (environment) => credentialEnvironmentForDirenv(environment, context7);
const prepareContext7Environment = (inherited, loaded) => prepareCredentialEnvironment(inherited, loaded, "/home/user", context7);
const assertContext7CredentialGrants = (args, cwd, home, environment = {}, profile = {}, path = context7SecretPath) =>
  assertCredentialSourceGrants(args, cwd, home, environment, profile, {
    context7: { ...context7.context7, source: { ...context7.context7.source, path } },
  });

const token = "synthetic-context7-credential";

test("Context7 credentials are withheld from direnv and rejected before nono", () => {
  assert.deepEqual(direnvContext7Environment({ CONTEXT7_API_KEY: token, OTHER: "kept" }), { OTHER: "kept" });
  assert.throws(() => prepareContext7Environment({ CONTEXT7_API_KEY: token }, {}), /Context7 credential environment/);
  assert.throws(() => prepareContext7Environment({}, { CONTEXT7_API_KEY: token }), /Context7 credential environment/);
  assert.deepEqual(prepareContext7Environment({}, { OTHER: "kept", CONTEXT7_API_KEY: "" }), { OTHER: "kept" });
});

test("Context7 declares its file source and bearer route", () => {
  assert.deepEqual(context7.context7.route, {
    upstream: "https://mcp.context7.com",
    env_var: "CONTEXT7_API_KEY",
    inject_header: "Authorization",
    credential_format: "Bearer {}",
  });
  assert.deepEqual(context7.context7.source, {
    type: "file", path: context7SecretPath,
    sops: { file: "apis", key: "context7-api-key" },
  });
  assert.deepEqual(context7.context7.capture, { timeout_secs: 10, cache_ttl_secs: 300 });
});

test("SOPS-style symlinks cannot expose a Context7 key through file, runtime, or ancestor grants", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-context7-grants-"));
  try {
    const safe = join(root, "safe");
    const store = join(root, "secrets");
    const generation = join(root, "secrets.d", "1");
    for (const directory of [safe, store, generation]) mkdirSync(directory, { recursive: true });
    const target = join(generation, "context7-api-key");
    const secret = join(store, "context7-api-key");
    writeFileSync(target, token, { mode: 0o400 });
    symlinkSync(target, secret);
    const check = (args, cwd = safe, env = {}, profile = {}) =>
      assertContext7CredentialGrants(args, cwd, root, env, profile, secret);
    assert.doesNotThrow(() => check(["--read", safe, "--", "pi"]));
    for (const flag of ["--read", "--allow", "--read-file", "--allow-file", "--allow-unix-socket", "--bypass-protection"]) {
      for (const grant of [secret, target, generation, root]) {
        assert.throws(() => check([flag, grant, "--", "pi"]), /Context7 credential/);
      }
    }
    assert.throws(() => check([], generation), /Context7 credential/);
    assert.throws(() => check([], safe, { TMPDIR: generation }, { filesystem: { read: ["$TMPDIR"] } }), /Context7 credential/);
    assert.throws(() => check([], safe, {}, { filesystem: { allow: [root] } }), /Context7 credential/);
    linkSync(target, join(safe, "hard-link"));
    assert.throws(() => check([]), /regular file without hard links/);
    rmSync(join(safe, "hard-link"));
    rmSync(target);
    assert.throws(() => check([]), /Cannot resolve Context7 credential/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("a not-yet-materialized key remains protected without blocking unrelated startup", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-context7-missing-"));
  try {
    const secret = join(root, "secrets", "context7-api-key");
    const safe = join(root, "safe");
    mkdirSync(safe);
    assert.doesNotThrow(() => assertContext7CredentialGrants([], safe, root, {}, {}, secret));
    assert.throws(() => assertContext7CredentialGrants(["--read", root], safe, root, {}, {}, secret), /Context7 credential/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("launcher rejects a project key without exposing it to direnv, nono, or stderr", () => {
  const root = mkdtempSync(join(tmpdir(), "pi-context7-bootstrap-"));
  try {
    const home = join(root, "home");
    const cwd = join(root, "project");
    const agent = join(home, ".pi", "agent");
    mkdirSync(agent, { recursive: true });
    mkdirSync(cwd);
    writeFileSync(join(cwd, ".envrc"), "fixture");
    const direnv = join(root, "direnv");
    const nono = join(root, "nono");
    writeFileSync(direnv, `#!${process.execPath}\nimport assert from "node:assert/strict";assert.equal(process.env.CONTEXT7_API_KEY,undefined);console.log(JSON.stringify({CONTEXT7_API_KEY:"${token}"}));\n`, { mode: 0o700 });
    writeFileSync(nono, `#!${process.execPath}\nthrow new Error("nono must not run");\n`, { mode: 0o700 });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
    for (const inheritedKey of [undefined, token]) {
      const env = { HOME: home, PATH: process.env.PATH, TMPDIR: root, PI_CODING_AGENT_DIR: agent };
      if (inheritedKey) env.CONTEXT7_API_KEY = inheritedKey;
      const result = spawnSync(process.execPath, [launcher, nono, process.execPath, profile, direnv, process.env.ENV_TEST_BINARY ?? "/usr/bin/env", "--version"], {
        cwd, env, encoding: "utf8", timeout: 15000,
      });
      assert.equal(result.status, 1, result.stderr);
      assert.match(result.stderr, /Context7 credential environment/);
      assert.ok(!(result.stdout + result.stderr).includes(token));
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
