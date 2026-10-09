import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, dirname, join } from "node:path";
import { test } from "node:test";

const { PI_TEST_PROFILE: profile, PI_TEST_PROBE: probe, PI_TEST_FISH: fish } = process.env;
assert.ok(profile && probe && fish, "Run through checks.pi-launcher-routing");

test("assembled system profile exposes the activation marker beside pi", () => {
  assert.ok(existsSync(join(profile, "bin", "pi")));
  assert.ok(existsSync(join(profile, "share", "pi", "nono-wrapper")));
});

test("wrapper and Pi's actual shell helper keep writable launchers behind immutable pi", () => {
  const root = realpathSync(mkdtempSync(join(tmpdir(), "pi-routing-")));
  try {
    const home = join(root, "home");
    const agent = join(home, "dotfiles", ".pi", "agent");
    const managedBin = join(agent, "bin");
    const legacyBin = join(home, ".pi", "agent", "bin");
    const unrelated = join(root, "other-bin");
    for (const dir of [managedBin, legacyBin, unrelated]) {
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "pi"), "#!/bin/sh\necho WRONG-LAUNCHER\n", { mode: 0o755 });
    }
    for (const [configuredAgent, inherited] of [
      [agent, [managedBin, legacyBin, unrelated]],
      ["~/dotfiles/.pi/agent", [legacyBin, unrelated]],
      ["home/dotfiles/.pi/agent", []],
      [agent, [`${managedBin}/`, managedBin, legacyBin, unrelated, managedBin]],
    ]) {
      const env = {
        ...process.env,
        HOME: home,
        PI_CODING_AGENT_DIR: configuredAgent,
        PATH: inherited.join(delimiter),
      };
      const child = spawnSync(probe, ["--no-sandbox"], { cwd: root, env, encoding: "utf8" });
      assert.ifError(child.error);
      assert.equal(child.status, 0, child.stderr);
      const result = JSON.parse(child.stdout);
      assert.equal(result.pi, probe);
      assert.equal(result.launchPath.split(delimiter)[0], dirname(probe));
      assert.equal(result.shellPath, result.launchPath, "Pi must not prepend its managed bin again");
      const paths = result.shellPath.split(delimiter);
      assert.equal(paths.at(-1), managedBin);
      assert.equal(paths.filter((path) => path === managedBin).length, 1);
      if (inherited.includes(legacyBin)) assert.ok(paths.indexOf(legacyBin) > paths.indexOf(unrelated));
      if (inherited.includes(unrelated)) assert.ok(paths.includes(unrelated));
      const freshFish = spawnSync(fish, ["--no-config", "-c", "command -s pi"], {
        env: { ...env, PATH: [join(profile, "bin"), ...paths].join(delimiter) },
        encoding: "utf8",
      });
      assert.ifError(freshFish.error);
      assert.equal(freshFish.status, 0, freshFish.stderr);
      assert.equal(realpathSync(freshFish.stdout.trim()), realpathSync(join(profile, "bin", "pi")));
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
