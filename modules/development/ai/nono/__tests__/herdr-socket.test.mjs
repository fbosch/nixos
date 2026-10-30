import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { launchArguments } from "../scripts/launcher.mjs";

const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";
const execute = promisify(execFile);
const report = {
  id: "session-name-fixture",
  method: "pane.report_metadata",
  params: {
    pane_id: "wFixture:p1", source: "user:pi-session-title", agent: "pi", seq: 1,
    applies_to_source: "herdr:pi", tokens: { pi_session_title: "Session æøå" },
  },
};
const probe = `
  if (process.argv[2]) {
    const assert = require("node:assert/strict");
    assert.ok(process.env.HTTP_PROXY, "credential proxy must be active");
    assert.throws(() => require("node:fs").readFileSync(process.argv[2]),
      error => ["EACCES", "EPERM"].includes(error.code));
  }
  const { createConnection } = require("node:net");
  const socket = createConnection(process.env.HERDR_SOCKET_PATH);
  socket.on("connect", () => socket.write(process.argv[1] + "\\n"));
  socket.on("data", () => socket.destroy());
  socket.on("error", error => { console.error(error.code); process.exitCode = 1; });
  socket.setTimeout(2000, () => { console.error("report timed out"); socket.destroy(); process.exitCode = 1; });
`;

function fixture() {
  // Keep the socket outside cwd and /tmp so broad default grants cannot mask failures.
  const root = realpathSync(mkdtempSync(join(process.cwd(), ".pi-herdr-")));
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const cwd = join(root, "work");
  const config = join(home, ".config", "herdr");
  const environment = {
    PATH: process.env.PATH, HOME: home, NO_COLOR: "1", HERDR_ENV: "1",
    HERDR_PANE_ID: "wFixture:p1", HERDR_SOCKET_PATH: join(config, "herdr.sock"),
    XDG_CONFIG_HOME: join(home, ".config"), XDG_STATE_HOME: join(root, "state"),
    XDG_CACHE_HOME: join(root, "cache"), XDG_DATA_HOME: join(root, "data"), TMPDIR: join(root, "tmp"),
  };
  for (const path of [agent, cwd, config, ...["XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "TMPDIR"].map(key => environment[key])]) {
    mkdirSync(path, { recursive: true });
  }
  // Production uses a credential proxy, which tightens Seatbelt's network policy.
  const policy = JSON.parse(readFileSync(profile, "utf8"));
  policy.network.credentials = ["fixture"];
  policy.network.custom_credentials = {
    fixture: { upstream: "https://example.invalid", credential_key: "cmd://fixture", env_var: "FIXTURE_TOKEN" },
  };
  policy.credential_capture = {
    fixture: { command: [process.execPath, "-e", 'console.log("synthetic-credential")'] },
  };
  const candidate = join(root, "profile.json");
  writeFileSync(candidate, JSON.stringify(policy));
  const args = (platform = process.platform) => launchArguments(cwd, agent, home, environment, candidate, process.execPath, envBinary, platform);
  return { root, home, cwd, environment, args };
}

test("Herdr socket grants stay endpoint-scoped on Linux and macOS", async () => {
  const f = fixture();
  const server = createServer();
  try {
    server.listen(f.environment.HERDR_SOCKET_PATH);
    await once(server, "listening");
    for (const platform of ["linux", "darwin"]) {
      const args = f.args(platform);
      assert.ok(args.some((part, index) => part === "--allow-unix-socket" && args[index + 1] === f.environment.HERDR_SOCKET_PATH));
      for (const flag of ["--allow", "--read", "--allow-unix-socket-dir", "--allow-unix-socket-subtree"]) {
        assert.ok(!args.some((part, index) => part === flag && args[index + 1] === join(f.home, ".config", "herdr")));
      }
    }
    f.environment.HERDR_ENV = "0";
    assert.ok(!f.args().includes(f.environment.HERDR_SOCKET_PATH));
    delete f.environment.HERDR_ENV;
    assert.ok(!f.args().includes(f.environment.HERDR_SOCKET_PATH));
    f.environment.HERDR_ENV = "1";
    delete f.environment.HERDR_SOCKET_PATH;
    assert.doesNotThrow(() => f.args());
  } finally {
    await new Promise(resolve => server.close(resolve));
    rmSync(f.root, { recursive: true, force: true });
  }
});

test("Herdr socket grants reject relative paths, directories and regular files", () => {
  const f = fixture();
  try {
    f.environment.HERDR_SOCKET_PATH = "relative.sock";
    assert.throws(() => f.args(), /HERDR_SOCKET_PATH must be an absolute socket path/);
    f.environment.HERDR_SOCKET_PATH = f.home;
    assert.throws(() => f.args(), /HERDR_SOCKET_PATH must point to a socket/);
    const file = join(f.root, "not-a-socket");
    writeFileSync(file, "fixture");
    f.environment.HERDR_SOCKET_PATH = file;
    assert.throws(() => f.args(), /HERDR_SOCKET_PATH must point to a socket/);
  } finally {
    rmSync(f.root, { recursive: true, force: true });
  }
});
test("sandboxed Pi delivers session-name metadata to the inherited Herdr socket", {
  skip: !process.env.NONO_TEST_BINARY,
  timeout: 30000,
}, async () => {
  const f = fixture();
  const received = [];
  const otherServer = createServer(socket => {
    socket.resume();
    socket.end('{"ok":true}\n');
  });
  const otherSocket = f.environment.HERDR_SOCKET_PATH + ".other";
  const secret = f.environment.HERDR_SOCKET_PATH + ".secret";
  const server = createServer(socket => {
    let input = "";
    socket.setEncoding("utf8").on("data", chunk => {
      input += chunk;
      if (!input.includes("\n")) return;
      received.push(JSON.parse(input.trim()));
      socket.end('{"ok":true}\n');
    });
  });
  try {
    server.listen(f.environment.HERDR_SOCKET_PATH);
    await once(server, "listening");
    otherServer.listen(otherSocket);
    await once(otherServer, "listening");
    writeFileSync(secret, "private Herdr config");
    const options = { cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 15000, killSignal: "SIGKILL" };
    await execute(process.execPath, ["-e", probe, JSON.stringify(report)], options);
    assert.deepEqual(received.splice(0), [report], "fixture must accept the unsandboxed report");

    const args = f.args();
    // Trust-store integration is unrelated to Unix IPC; do not modify the user's Keychain.
    if (args.includes("--trust-proxy-ca")) args.splice(args.indexOf("--trust-proxy-ca"), 1);
    args.splice(args.indexOf("--"), 0, "--no-audit", "--no-rollback");
    await execute(process.env.NONO_TEST_BINARY, [
      ...args, "-e", probe, JSON.stringify(report), ...(process.platform === "darwin" ? [secret] : []),
    ], options);
    assert.deepEqual(received, [report], "the session title must reach Herdr through confinement");
    if (process.platform === "darwin") {
      await execute(process.execPath, ["-e", probe, JSON.stringify(report)], {
        ...options, env: { ...f.environment, HERDR_SOCKET_PATH: otherSocket },
      });
      await assert.rejects(execute(process.env.NONO_TEST_BINARY, [...args, "-e", probe, JSON.stringify(report)], {
        ...options, env: { ...f.environment, HERDR_SOCKET_PATH: otherSocket },
      }), error => /EPERM|EACCES/.test(error.stderr));
    }
  } finally {
    await new Promise(resolve => otherServer.close(resolve));
    await new Promise(resolve => server.close(resolve));
    rmSync(f.root, { recursive: true, force: true });
  }
});
