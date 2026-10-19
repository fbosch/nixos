import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const profile = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const binary = process.env.NONO_TEST_BINARY;
const runtimeSkip = process.platform === "darwin" && process.env.NONO_CAP_FILE
  ? "macOS runtime checks require a runner outside Nono"
  : !binary;

function withFixture(check) {
  // Shared /tmp grants or a writable CWD covering HOME would mask credential denials.
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-azure-")));
  const home = join(root, "home");
  const work = join(root, "work");
  const azure = join(home, ".azure");
  const devops = join(home, ".azure-devops");
  const devopsCache = join(devops, "python-sdk", "cache");
  const environment = {
    PATH: process.env.PATH, HOME: home, NO_COLOR: "1",
    XDG_CONFIG_HOME: join(root, "config"), XDG_STATE_HOME: join(root, "state"),
    XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(root, "data"),
    TMPDIR: join(root, "tmp"), AZURE_CONFIG_DIR: azure,
    AZURE_EXTENSION_DIR: join(azure, "cliextensions"),
    AZURE_CORE_COLLECT_TELEMETRY: "no", AZURE_CORE_CHECK_VERSION: "no",
    AZURE_EXTENSION_USE_DYNAMIC_INSTALL: "no",
  };
  try {
    for (const directory of [
      work, azure, devopsCache, join(home, ".ssh"), join(home, ".aws"),
      ...["XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "TMPDIR"].map(key => environment[key]),
    ]) mkdirSync(directory, { recursive: true });
    writeFileSync(join(azure, "azureProfile.json"), '{"subscriptions":[]}', { mode: 0o600 });
    writeFileSync(join(devopsCache, "existing.json"), "{}", { mode: 0o600 });
    writeFileSync(join(devops, "credentials"), "credential fixture", { mode: 0o600 });
    writeFileSync(join(devops, "python-sdk", "outside-cache.json"), "{}", { mode: 0o600 });
    writeFileSync(join(home, ".ssh", "id_ed25519"), "private key fixture", { mode: 0o600 });
    writeFileSync(join(home, ".aws", "credentials"), "credential fixture", { mode: 0o600 });
    const run = args => {
      const result = spawnSync(binary, args, { cwd: work, env: environment, encoding: "utf8", timeout: 15000 });
      assert.ifError(result.error);
      assert.equal(result.signal, null, result.stderr);
      assert.equal(result.status, 0, result.stderr || result.stdout);
      return result.stdout;
    };
    check({ home, azure, devops, devopsCache, run });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

function sandbox(program, ...args) {
  return ["run", "--profile", profile, "--allow-cwd", "--no-audit", "--no-rollback", "--block-net", "--", program, ...args];
}

test("Nono grants Azure state and only the DevOps SDK cache without lifting credential protections", { skip: !binary }, () => {
  withFixture(({ home, azure, devops, devopsCache, run }) => {
    for (const [path, operation, expected] of [
      [join(azure, "azureProfile.json"), "read", "allowed"],
      [join(azure, "azureProfile.json"), "write", "allowed"],
      [devopsCache, "read", "allowed"],
      [devopsCache, "write", "allowed"],
      [join(devopsCache, "existing.json"), "read", "allowed"],
      [join(devopsCache, "new.json"), "write", "allowed"],
      [join(devops, "credentials"), "read", "denied"],
      [join(devops, "credentials"), "write", "denied"],
      [join(devops, "python-sdk", "outside-cache.json"), "read", "denied"],
      [join(devops, "python-sdk", "outside-cache.json"), "write", "denied"],
      [join(home, ".ssh", "id_ed25519"), "read", "denied"],
      [join(home, ".aws", "credentials"), "read", "denied"],
    ]) {
      const result = JSON.parse(run(["why", "--profile", profile, "--path", path, "--op", operation, "--json"]));
      assert.equal(result.status, expected, `${path}: ${operation}`);
    }
  });
});

test("sandbox permits Azure state reads and new cache files while denying neighboring secrets", { skip: runtimeSkip }, () => {
  withFixture(({ home, run }) => {
    run(sandbox(process.execPath, "-e", `
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const path = require("node:path");
      const home = process.argv[1];
      const azure = path.join(home, ".azure");
      const profile = path.join(azure, "azureProfile.json");
      assert.deepEqual(JSON.parse(fs.readFileSync(profile, "utf8")), { subscriptions: [] });
      fs.writeFileSync(profile, JSON.stringify({ subscriptions: [], updated: true }));
      const commands = path.join(azure, "commands");
      fs.mkdirSync(commands);
      const log = path.join(commands, "fixture.log");
      fs.writeFileSync(log, "command fixture");
      assert.equal(fs.readFileSync(log, "utf8"), "command fixture");
      fs.unlinkSync(log);
      const devops = path.join(home, ".azure-devops");
      const devopsCache = path.join(devops, "python-sdk", "cache");
      assert.equal(fs.statSync(devopsCache).isDirectory(), true);
      assert.deepEqual(JSON.parse(fs.readFileSync(path.join(devopsCache, "existing.json"), "utf8")), {});
      const cacheEntry = path.join(devopsCache, "new.json");
      fs.writeFileSync(cacheEntry, "{}");
      assert.deepEqual(JSON.parse(fs.readFileSync(cacheEntry, "utf8")), {});
      fs.unlinkSync(cacheEntry);
      for (const denied of [path.join(devops, "credentials"), path.join(devops, "python-sdk", "outside-cache.json")]) {
        assert.throws(() => fs.readFileSync(denied), error => ["EACCES", "EPERM"].includes(error.code));
        assert.throws(() => fs.writeFileSync(denied, "{}"), error => ["EACCES", "EPERM"].includes(error.code));
      }
      for (const secret of [path.join(home, ".ssh", "id_ed25519"), path.join(home, ".aws", "credentials")]) {
        assert.throws(() => fs.readFileSync(secret), error => ["EACCES", "EPERM"].includes(error.code));
      }
    `, home));
  });
});

test("Azure CLI starts with sandboxed writable state without login or network access", {
  skip: runtimeSkip || !process.env.AZURE_CLI_TEST_BINARY,
}, () => {
  withFixture(({ run }) => {
    const result = JSON.parse(run(sandbox(process.env.AZURE_CLI_TEST_BINARY, "version")));
    assert.equal(typeof result["azure-cli"], "string");
  });
});
