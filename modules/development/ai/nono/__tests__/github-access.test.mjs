import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { launchArguments } from "../scripts/launcher.mjs";
import { prepareSandboxRuntime } from "../scripts/sandbox-runtime.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

const profilePath = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));

test("GitHub CLI and MCP caches work while credentials and neighboring secrets stay blocked", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY || !process.env.GH_TEST_BINARY,
  timeout: 15000,
}, () => {
  // Keep credentials outside the workdir and /tmp so only the profile can authorize them.
  const root = mkdtempSync(join(process.cwd(), ".pi-github-"));
  const home = join(root, "home");
  const work = join(root, "work");
  const config = join(home, ".config", "gh");
  const extensions = join(home, ".local", "share", "gh", "extensions");
  const mcp = join(extensions, "gh-mcp", "gh-mcp");
  try {
    for (const directory of [
      config, join(home, ".config", "other"), join(home, ".ssh"), work,
      join(root, "tmp"), join(root, "state"), join(root, "cache"), join(root, "data"),
    ]) mkdirSync(directory, { recursive: true });
    mkdirSync(join(extensions, "gh-mcp"), { recursive: true });
    writeFileSync(mcp, "#!/bin/sh\nprintf 'mcp-fixture\\n'\n", { mode: 0o755 });
    writeFileSync(join(config, "hosts.yml"), "github.com:\n    oauth_token: synthetic-github-credential\n", { mode: 0o600 });
    writeFileSync(join(config, "config.yml"), "editor: vi\n", { mode: 0o600 });
    writeFileSync(join(home, ".config", "other", "secret"), "neighboring secret", { mode: 0o600 });
    writeFileSync(join(home, ".ssh", "id_ed25519"), "fixture private key", { mode: 0o600 });
    prepareSandboxRuntime(home);
    const agent = join(home, ".pi", "agent");
    mkdirSync(agent, { recursive: true });
    // This fixture tests filesystem isolation, not network credential capture.
    const offlineProfile = join(root, "profile.json");
    const profile = JSON.parse(readFileSync(profilePath, "utf8"));
    writeFileSync(offlineProfile, JSON.stringify({ ...profile, network: { block: false }, credential_capture: {} }));
    const environment = {
      PATH: process.env.PATH, HOME: home, TMPDIR: join(root, "tmp"),
      XDG_CONFIG_HOME: join(home, ".config"), XDG_STATE_HOME: join(root, "state"),
      XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(home, ".local", "share"),
      GH_CONFIG_DIR: config, GH_TOKEN: "synthetic-proxy-placeholder", NO_COLOR: "1",
    };
    const args = launchArguments(work, agent, home, environment, offlineProfile, process.execPath, envBinary);
    args.splice(args.indexOf("--"), 0, "--no-audit", "--no-rollback", "--read", fileURLToPath(new URL("../scripts", import.meta.url)));

    const probe = `
      process.emitWarning("proxy-agent notice", { code: "UNDICI-EHPA" });
      process.emitWarning("other warning", { code: "PI_TEST_OTHER_WARNING" });
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const path = require("node:path");
      const { spawnSync } = require("node:child_process");
      const [gh, home] = process.argv.slice(1);
      const config = path.join(home, ".config", "gh");
      const hosts = path.join(config, "hosts.yml");
      assert.equal(process.env.GH_CONFIG_DIR, path.join(home, ".cache", "pi", "gh"));
      assert.equal(process.env.GH_TOKEN, "synthetic-proxy-placeholder");
      const denied = (operation) => assert.throws(operation, (error) => ["EACCES", "EPERM"].includes(error.code));
      denied(() => fs.readFileSync(hosts));
      denied(() => fs.readFileSync(path.join(config, "config.yml")));
      const npx = path.join(process.env.npm_config_cache, "_npx", "fixture");
      fs.mkdirSync(npx, { recursive: true });
      fs.writeFileSync(path.join(npx, "concurrency.lock"), "lock");
      for (const name of ["UV_CACHE_DIR", "UV_PYTHON_INSTALL_DIR", "UV_TOOL_DIR"]) {
        const temporary = fs.mkdtempSync(path.join(process.env[name], ".tmp-"));
        fs.writeFileSync(path.join(temporary, "state"), "cache fixture");
        assert.equal(fs.readFileSync(path.join(temporary, "state"), "utf8"), "cache fixture");
      }
      const extension = spawnSync(gh, ["mcp"], { env: process.env, encoding: "utf8", timeout: 5000 });
      assert.ifError(extension.error);
      assert.equal(extension.status, 0, extension.stderr);
      assert.equal(extension.stdout.trim(), "mcp-fixture");
      denied(() => fs.appendFileSync(path.join(home, ".local", "share", "gh", "extensions", "gh-mcp", "gh-mcp"), "changed"));
      denied(() => fs.appendFileSync(hosts, "changed"));
      denied(() => fs.writeFileSync(path.join(config, "new.yml"), "changed"));
      denied(() => fs.unlinkSync(hosts));
      denied(() => fs.readFileSync(path.join(home, ".config", "other", "secret")));
      denied(() => fs.readFileSync(path.join(home, ".ssh", "id_ed25519")));
    `;
    const result = spawnSync(process.env.NONO_TEST_BINARY, [...args, "-e", probe, process.env.GH_TEST_BINARY, home], {
      cwd: work,
      env: environment,
      encoding: "utf8",
      timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.doesNotMatch(result.stderr, /UNDICI-EHPA/);
    assert.match(result.stderr, /PI_TEST_OTHER_WARNING/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("direct SSH and platform web exceptions coexist with the isolated GitHub credential proxy", {
  skip: process.platform === "darwin" && process.env.NONO_CAP_FILE
    ? "macOS runtime checks require a runner outside Nono"
    : !process.env.NONO_TEST_BINARY,
  timeout: 15000,
}, () => {
  const root = mkdtempSync(join(process.cwd(), ".pi-network-"));
  const home = join(root, "home");
  const work = join(root, "work");
  const agent = join(home, ".pi", "agent");
  try {
    for (const directory of [agent, work, join(home, ".ssh"), join(root, "tmp"), join(root, "state"), join(root, "cache"), join(home, ".config")]) {
      mkdirSync(directory, { recursive: true });
    }
    writeFileSync(join(home, ".ssh", "id_ed25519"), "fixture private key", { mode: 0o600 });
    prepareSandboxRuntime(home);
    const profile = JSON.parse(readFileSync(profilePath, "utf8"));
    profile.credential_capture.github.command = [process.execPath, "-e", `
      const assert = require("node:assert/strict");
      const path = require("node:path");
      assert.equal(process.env.GH_CONFIG_DIR, path.join(process.env.HOME, ".config", "gh"));
      assert.equal(process.env.NODE_OPTIONS, undefined);
      console.log("synthetic-github-credential");
    `];
    const networkProfile = join(root, "profile.json");
    writeFileSync(networkProfile, JSON.stringify(profile));
    const environment = {
      PATH: process.env.PATH, HOME: home, TMPDIR: join(root, "tmp"),
      XDG_CONFIG_HOME: join(home, ".config"), XDG_STATE_HOME: join(root, "state"),
      GH_CONFIG_DIR: join(home, ".config", "gh"),
      XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(home, ".local", "share"),
      NO_COLOR: "1",
    };
    // The probe uses no TLS; do not modify host CA trust in tests.
    const args = launchArguments(work, agent, home, environment, networkProfile, process.execPath, envBinary)
      .filter(arg => arg !== "--trust-proxy-ca");
    args.splice(args.indexOf("--"), 0, "--no-audit", "--no-rollback", "--read", fileURLToPath(new URL("../scripts", import.meta.url)));
    const probe = `
      const assert = require("node:assert/strict");
      const { createConnection } = require("node:net");
      const proxy = new URL(process.env.HTTP_PROXY);
      assert.equal(proxy.hostname, "127.0.0.1");
      assert.equal(process.env.HTTPS_PROXY, process.env.HTTP_PROXY);
      assert.equal(typeof process.env.GH_TOKEN, "string");
      assert.notEqual(process.env.GH_TOKEN, "synthetic-github-credential");
      const connect = (port, host = "127.0.0.1") => new Promise((resolve) => {
        const socket = createConnection({ host, port });
        socket.setTimeout(2000, () => { socket.destroy(); resolve("timeout"); });
        socket.once("connect", () => { socket.destroy(); resolve("connected"); });
        socket.once("error", (error) => resolve(error.code));
      });
      (async () => {
        // Refusal from an empty loopback port proves connect reached the network stack.
        for (const port of [22, 80, 443]) assert.match(await connect(port), /^(connected|ECONNREFUSED)$/, String(port));
        if (process.platform === "linux") assert.match(await connect(23), /^(EACCES|EPERM)$/);
        assert.match(await connect(23, "192.0.2.1"), /^(EACCES|EPERM)$/);
        const key = require("node:path").join(process.env.HOME, ".ssh", "id_ed25519");
        assert.throws(() => require("node:fs").readFileSync(key), error => ["EACCES", "EPERM"].includes(error.code));
        assert.equal(await connect(Number(proxy.port)), "connected");
      })().catch((error) => { console.error(error); process.exitCode = 1; });
    `;
    const result = spawnSync(process.env.NONO_TEST_BINARY, [...args, "-e", probe], {
      cwd: work, env: environment, encoding: "utf8", timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.doesNotMatch(result.stdout + result.stderr, /synthetic-github-credential/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
