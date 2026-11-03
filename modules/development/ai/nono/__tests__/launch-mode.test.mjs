import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { sandboxRuntimeCommand } from "../scripts/launch/runtime.mts";

const launcher = fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url));
const probe = 'console.log(JSON.stringify({mode:process.env.PI_NONO_MODE,cap:process.env.NONO_CAP_FILE ?? null,args:process.argv.slice(1)}))';

for (const cap of [undefined, "/synthetic/inherited-cap.json"]) {
  test(`explicit raw launch reports disabled and preserves inherited metadata: ${cap ?? "absent"}`, () => {
    const home = mkdtempSync(join(tmpdir(), "pi-launch-mode-"));
    try {
      const env = { HOME: home, PATH: process.env.PATH, PI_NONO_MODE: "sandboxed" };
      if (cap !== undefined) env.NONO_CAP_FILE = cap;
      const child = spawnSync(process.execPath, [
        launcher, "/missing-nono", process.execPath, "/missing-profile", "/missing-direnv", "/missing-env",
        "--no-sandbox", "-e", probe, "--", "--resume", "synthetic-session",
      ], { cwd: home, env, encoding: "utf8", timeout: 10000 });
      assert.ifError(child.error);
      assert.equal(child.status, 0, child.stderr);
      assert.deepEqual(JSON.parse(child.stdout), {
        mode: "disabled", cap: cap ?? null, args: ["--resume", "synthetic-session"],
      });
    } finally {
      rmSync(home, { recursive: true, force: true });
    }
  });
}

test("sandbox child command overrides inherited disabled markers without dropping capabilities", () => {
  const home = mkdtempSync(join(tmpdir(), "pi-launch-mode-"));
  try {
    const command = sandboxRuntimeCommand(home, process.execPath, process.env.ENV_TEST_BINARY ?? "/usr/bin/env");
    const child = spawnSync(command[0], [...command.slice(1), "-e", probe], {
      cwd: home,
      env: { HOME: home, PATH: process.env.PATH, PI_NONO_MODE: "disabled", NONO_CAP_FILE: "/synthetic/current-cap.json" },
      encoding: "utf8", timeout: 10000,
    });
    assert.ifError(child.error);
    assert.equal(child.status, 0, child.stderr);
    assert.deepEqual(JSON.parse(child.stdout), { mode: "sandboxed", cap: "/synthetic/current-cap.json", args: [] });
  } finally {
    rmSync(home, { recursive: true, force: true });
  }
});
