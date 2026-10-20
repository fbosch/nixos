import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const profilePath = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const probePath = fileURLToPath(new URL("./fixtures/macos-browser-startup-probe.py", import.meta.url));

test("macOS runtime rules allow outbound SSH and scoped browser startup", () => {
  const profile = JSON.parse(readFileSync(profilePath, "utf8"));
  assert.deepEqual(profile.unsafe_macos_seatbelt_rules, [
    '(allow network-outbound (remote tcp "*:22"))',
    "(allow ipc-sysv-sem)",
    "(allow lsopen)",
    '(allow iokit-open (iokit-user-client-class "RootDomainUserClient"))',
    '(allow mach-register (global-name-regex #"^(org[.]chromium[.]Chromium|com[.]google[.]Chrome|com[.]google[.]chrome[.]for[.]testing)[.]MachPortRendezvousServer[.][0-9]+$"))',
  ]);
  assert.equal(profile.extends, "default");
  assert.equal(profile.security.capability_elevation, false);
  assert.equal(profile.allow_gpu ?? false, false);
});

test("macOS compiles the browser Seatbelt rules without changing the current sandbox", {
  skip: process.platform !== "darwin" || !process.env.PYTHON_TEST_BINARY,
}, () => {
  const profile = JSON.parse(readFileSync(profilePath, "utf8"));
  const child = spawnSync(process.env.PYTHON_TEST_BINARY, ["-I", probePath, "--compile"], {
    input: `(version 1)\n(deny default)\n${profile.unsafe_macos_seatbelt_rules.join("\n")}\n`,
    encoding: "utf8", timeout: 10000, killSignal: "SIGKILL",
  });
  assert.ifError(child.error);
  assert.equal(child.signal, null, child.stderr);
  assert.equal(child.status, 0, child.stderr);
  assert.match(child.stdout, /Seatbelt rules compiled/);
});

test("macOS browser startup capabilities work without exposing credentials or arbitrary Mach services", {
  skip: process.platform !== "darwin" || !process.env.NONO_TEST_BINARY || !process.env.PYTHON_TEST_BINARY,
  timeout: 20000,
}, () => {
  // Keep denied fixtures outside the writable workdir and the default /tmp grant.
  const root = mkdtempSync(join(process.cwd(), ".pi-browser-"));
  const home = join(root, "home");
  const work = join(root, "work");
  const environment = {
    ...process.env,
    HOME: home,
    XDG_CONFIG_HOME: join(root, "config"),
    XDG_CACHE_HOME: join(root, "cache"),
    XDG_DATA_HOME: join(root, "data"),
    XDG_STATE_HOME: join(root, "state"),
    TMPDIR: join(root, "tmp"),
    PYTHONDONTWRITEBYTECODE: "1",
  };
  const secrets = [
    join(home, ".ssh", "id_ed25519"),
    join(home, "Library", "Application Support", "Google", "Chrome", "Default", "Cookies"),
  ];
  try {
    for (const path of [work, join(home, ".pi"), join(home, ".npm", "_cacache"), join(home, ".npm", "_logs"),
      ...["XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR"].map(key => environment[key])]) {
      mkdirSync(path, { recursive: true });
    }
    for (const path of secrets) {
      mkdirSync(dirname(path), { recursive: true });
      writeFileSync(path, "private fixture");
    }
    const child = spawnSync(process.env.NONO_TEST_BINARY, [
      "run", "--profile", profilePath, "--allow-cwd", "--read-file", probePath, "--",
      process.env.PYTHON_TEST_BINARY, "-I", probePath, ...secrets,
    ], { cwd: work, env: environment, encoding: "utf8", timeout: 15000, killSignal: "SIGKILL" });
    assert.ifError(child.error);
    assert.equal(child.signal, null, child.stderr);
    assert.equal(child.status, 0, child.stderr);
    assert.match(child.stdout, /browser startup capabilities verified/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
