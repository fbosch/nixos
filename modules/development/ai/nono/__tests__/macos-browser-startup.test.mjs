import assert from "node:assert/strict";
import { execFile, spawnSync } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { dirname, join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const profilePath = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const probePath = fileURLToPath(new URL("./fixtures/macos-browser-startup-probe.py", import.meta.url));

test("macOS runtime rules allow outbound SSH/HTTP/HTTPS and scoped browser startup", () => {
  const profile = JSON.parse(readFileSync(profilePath, "utf8"));
  assert.deepEqual(profile.unsafe_macos_seatbelt_rules, [
    '(allow network-outbound (remote tcp "*:22"))',
    '(allow network-outbound (remote tcp "*:80"))',
    '(allow network-outbound (remote tcp "*:443"))',
    '(allow network-outbound (remote tcp "localhost:*"))',
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

test("macOS proxy sandbox permits dynamic loopback TCP without opening external ports or secrets", {
  skip: process.platform !== "darwin" || !process.env.NONO_TEST_BINARY || Boolean(process.env.NONO_CAP_FILE),
  timeout: 20000,
}, async () => {
  const root = mkdtempSync(join(process.cwd(), ".pi-loopback-"));
  const home = join(root, "home");
  const work = join(root, "work");
  const servers = [];
  const environment = {
    PATH: process.env.PATH, HOME: home, NO_COLOR: "1",
    XDG_CONFIG_HOME: join(root, "config"), XDG_STATE_HOME: join(root, "state"),
    XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(root, "data"),
    TMPDIR: join(root, "tmp"),
  };
  try {
    for (const path of [work, join(home, ".ssh"),
      ...["XDG_CONFIG_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "TMPDIR"].map(key => environment[key])]) {
      mkdirSync(path, { recursive: true });
    }
    const secret = join(home, ".ssh", "id_ed25519");
    writeFileSync(secret, "private fixture", { mode: 0o600 });
    const endpoints = [];
    for (const host of ["127.0.0.1", "::1"]) {
      const server = createServer(socket => socket.end("loopback-fixture"));
      servers.push(server);
      server.listen({ host, port: 0 });
      await once(server, "listening");
      endpoints.push({ host, port: server.address().port });
    }
    endpoints.push({ host: "localhost", port: endpoints[0].port });
    const policy = JSON.parse(readFileSync(profilePath, "utf8"));
    // Keep the credential proxy active without accessing any real credentials.
    policy.credential_capture.github.command = [process.execPath, "-e", 'console.log("synthetic-github-credential")'];
    const candidate = join(root, "profile.json");
    writeFileSync(candidate, JSON.stringify(policy));
    const probe = `
      const assert = require("node:assert/strict");
      const { createConnection } = require("node:net");
      const [endpoints, secret] = process.argv.slice(1);
      assert.ok(process.env.HTTP_PROXY, "the credential proxy must remain active");
      const connect = endpoint => new Promise((resolve, reject) => {
        const socket = createConnection(endpoint);
        let data = "";
        socket.setEncoding("utf8");
        socket.on("data", chunk => { data += chunk; });
        socket.once("end", () => resolve(data));
        socket.once("error", reject);
        socket.setTimeout(2000, () => {
          socket.destroy();
          reject(new Error("loopback connection timed out"));
        });
      });
      (async () => {
        for (const endpoint of JSON.parse(endpoints)) {
          assert.equal(await connect(endpoint), "loopback-fixture");
        }
        for (const port of [23, 80, 443]) {
          await assert.rejects(connect({ host: "192.0.2.1", port }),
            error => ["EACCES", "EPERM"].includes(error.code));
        }
        assert.throws(() => require("node:fs").readFileSync(secret),
          error => ["EACCES", "EPERM"].includes(error.code));
        console.log("loopback connections verified");
      })().catch(error => { console.error(error); process.exitCode = 1; });
    `;
    const child = await promisify(execFile)(process.env.NONO_TEST_BINARY, [
      "run", "--profile", candidate, "--allow-cwd", "--no-audit", "--no-rollback", "--",
      process.execPath, "-e", probe, JSON.stringify(endpoints), secret,
    ], { cwd: work, env: environment, encoding: "utf8", timeout: 15000, killSignal: "SIGKILL" });
    assert.match(child.stdout, /loopback connections verified/);
  } finally {
    await Promise.all(servers.filter(server => server.listening).map(server => new Promise(resolve => server.close(resolve))));
    rmSync(root, { recursive: true, force: true });
  }
});
