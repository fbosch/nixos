import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

const profilePath = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));

test("GitHub CLI reads its config while credentials stay read-only and neighboring secrets stay blocked", {
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
    writeFileSync(join(config, "hosts.yml"), "github.com:\n    user: sandbox-fixture\n    git_protocol: https\n", { mode: 0o600 });
    writeFileSync(join(config, "config.yml"), "editor: vi\n", { mode: 0o600 });
    writeFileSync(join(home, ".config", "other", "secret"), "neighboring secret", { mode: 0o600 });
    writeFileSync(join(home, ".ssh", "id_ed25519"), "fixture private key", { mode: 0o600 });

    const probe = `
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const path = require("node:path");
      const { spawnSync } = require("node:child_process");
      const [gh, home] = process.argv.slice(1);
      const config = path.join(home, ".config", "gh");
      const hosts = path.join(config, "hosts.yml");
      const result = spawnSync(gh, ["config", "get", "git_protocol", "--host", "github.com"], {
        env: process.env, encoding: "utf8", timeout: 5000,
      });
      assert.ifError(result.error);
      assert.equal(result.status, 0, result.stderr);
      assert.equal(result.stdout.trim(), "https");
      assert.equal(fs.readFileSync(path.join(config, "config.yml"), "utf8"), "editor: vi\\n");
      const extension = spawnSync(gh, ["mcp"], { env: process.env, encoding: "utf8", timeout: 5000 });
      assert.ifError(extension.error);
      assert.equal(extension.status, 0, extension.stderr);
      assert.equal(extension.stdout.trim(), "mcp-fixture");
      const denied = (operation) => assert.throws(operation, (error) => ["EACCES", "EPERM"].includes(error.code));
      denied(() => fs.appendFileSync(path.join(home, ".local", "share", "gh", "extensions", "gh-mcp", "gh-mcp"), "changed"));
      denied(() => fs.appendFileSync(hosts, "changed"));
      denied(() => fs.writeFileSync(path.join(config, "new.yml"), "changed"));
      denied(() => fs.unlinkSync(hosts));
      denied(() => fs.readFileSync(path.join(home, ".config", "other", "secret")));
      denied(() => fs.readFileSync(path.join(home, ".ssh", "id_ed25519")));
    `;
    const result = spawnSync(process.env.NONO_TEST_BINARY, [
      "run", "--profile", profilePath, "--allow-cwd",
      "--no-audit", "--no-rollback", "--suppress-save-prompt", "/", "--",
      process.execPath, "-e", probe, process.env.GH_TEST_BINARY, home,
    ], {
      cwd: work,
      env: {
        PATH: process.env.PATH, HOME: home, TMPDIR: join(root, "tmp"),
        XDG_CONFIG_HOME: join(home, ".config"), XDG_STATE_HOME: join(root, "state"),
        XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(home, ".local", "share"),
        NO_COLOR: "1",
      },
      encoding: "utf8",
      timeout: 10000,
    });
    assert.ifError(result.error);
    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.status, 0, result.stderr || result.stdout);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
