import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { createServer as createHttpServer } from "node:http";
import { createConnection, createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { launchArguments } from "../scripts/launcher.mjs";

const profilePath = process.env.NONO_TEST_PROFILE ?? fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const probe = fileURLToPath(new URL("./fixtures/socket-isolation-probe.mjs", import.meta.url));

test("Pi permits only the normal Nix daemon as an explicit socket grant", () => {
  const profile = JSON.parse(readFileSync(profilePath, "utf8"));
  assert.equal(profile.linux?.af_unix_mediation, "pathname");
  assert.deepEqual(profile.filesystem.unix_socket, [{ path: "/nix/var/nix/daemon-socket/socket", when: "linux" }]);
  for (const [key, value] of Object.entries(profile.filesystem)) {
    if (key.startsWith("unix_socket") && key !== "unix_socket") assert.deepEqual(value, [], key);
  }
  assert.equal(profile.security.capability_elevation, false);
});

function run(binary, args, options, { signal, timeoutMs = 30000 } = {}) {
  return new Promise((resolve, reject) => {
    signal?.throwIfAborted();
    // Own a process group so a stuck probe cannot retain pipes after nono exits.
    const child = spawn(binary, args, { ...options, detached: true, stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    let settled = false;
    const finish = (error, result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      signal?.removeEventListener("abort", abort);
      if (error) reject(error);
      else resolve(result);
    };
    const stop = (error) => {
      if (child.pid) {
        try { process.kill(-child.pid, "SIGKILL"); }
        catch (failure) { if (failure.code !== "ESRCH") error = failure; }
      }
      child.stdout.destroy();
      child.stderr.destroy();
      finish(error);
    };
    const abort = () => stop(signal.reason);
    const timeout = setTimeout(() => stop(new Error("Sandbox probe timed out")), timeoutMs);
    signal?.addEventListener("abort", abort, { once: true });
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.once("error", (error) => finish(error));
    child.once("close", (code, signal) => finish(null, { code, signal, stdout, stderr }));
  });
}

test("probe timeout terminates a process group retaining output pipes", { timeout: 5000 }, async (t) => {
  await assert.rejects(run(process.execPath, ["--input-type=module", "-e", `
    import { spawn } from "node:child_process";
    spawn(process.execPath, ["-e", 'process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)'], {
      stdio: "inherit",
    }).unref();
  `], {}, { signal: t.signal, timeoutMs: 500 }), /Sandbox probe timed out/);
});

test("pathname mediation denies unlisted sockets and aliases while explicit SSH, stdio and HTTP work", {
  skip: process.platform !== "linux" || !process.env.NONO_TEST_BINARY,
  timeout: 45000,
}, async (t) => {
  // Keep HOME/state outside /tmp: nono rejects grants covering its protected state.
  const root = mkdtempSync(join(process.cwd(), ".pi-sockets-"));
  const work = join(root, "work");
  const home = join(root, "home");
  const servers = [];
  const connections = new Set();
  try {
    const resolved = await run(process.env.NONO_TEST_BINARY, ["profile", "show", "--json", profilePath], {}, { signal: t.signal });
    assert.equal(resolved.code, 0, resolved.stderr);
    const policy = JSON.parse(resolved.stdout);
    assert.equal(policy.linux.af_unix_mediation, "pathname");
    assert.deepEqual(Object.fromEntries(Object.entries(policy.filesystem).filter(([key]) => key.startsWith("unix_socket"))), {
      unix_socket: ["/nix/var/nix/daemon-socket/socket"],
      unix_socket_bind: [],
      // The pinned default profile permits only NSS/user lookup sockets, not the session bus or service manager.
      unix_socket_dir: ["/run/systemd/userdb"],
      unix_socket_dir_bind: [],
      unix_socket_subtree: [],
      unix_socket_subtree_bind: [],
    });
    for (const path of [
      work, join(root, "runtime", "podman"), join(root, "runtime", "systemd"), join(home, ".pi", "agent"),
      join(home, ".npm", "_cacache"), join(home, ".npm", "_logs"),
      join(root, "tmp"), join(root, "state"), join(root, "cache"), join(root, "data"), join(root, "config"),
    ]) mkdirSync(path, { recursive: true });

    const runtime = join(root, "runtime");
    const launchId = "0123456789abcdef0123456789abcdef";
    const namespace = join(runtime, `pi-ask-${process.getuid()}`);
    const directory = join(namespace, launchId);
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    chmodSync(namespace, 0o700);
    const broker = join(directory, "broker.sock");
    const permitted = [join(runtime, "agent.sock"), broker];
    const neovim = join(runtime, "nvim.sock");
    const sockets = [
      join(runtime, "podman", "podman.sock"),
      join(runtime, "docker.sock"),
      join(runtime, "systemd", "private"),
      join(runtime, "bus"),
      neovim,
      join(work, "work.sock"),
      join(root, "tmp", "tmp.sock"),
      join(home, ".pi", "pi.sock"),
    ];
    let accepted = 0;
    for (const path of [...sockets, ...permitted]) {
      const server = createServer((socket) => {
        accepted++;
        connections.add(socket);
        socket.once("close", () => connections.delete(socket));
        socket.end();
      });
      servers.push(server);
      server.listen(path);
      await once(server, "listening");
      if (path === broker) chmodSync(path, 0o600);
    }
    const alias = join(work, "alias.sock");
    symlinkSync(sockets[0], alias);
    const directoryAlias = join(work, "runtime-alias");
    symlinkSync(runtime, directoryAlias);
    sockets.push(alias, join(directoryAlias, "bus"), "../runtime/bus");
    for (const path of [...sockets, ...permitted]) {
      const connection = createConnection(path === "../runtime/bus" ? join(work, path) : path);
      await once(connection, "connect");
      connection.destroy();
    }
    const baseline = sockets.length + permitted.length;
    assert.equal(accepted, baseline, "all fixture paths must be reachable before confinement");

    const http = createHttpServer((request, response) => {
      let body = "";
      request.setEncoding("utf8").on("data", (chunk) => { body += chunk; });
      request.on("end", () => {
        const message = JSON.parse(body);
        assert.equal(message.method, "initialize");
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify({
          jsonrpc: "2.0", id: message.id,
          result: { protocolVersion: "2024-11-05", capabilities: {}, serverInfo: { name: "http-fixture", version: "1" } },
        }));
      });
    });
    servers.push(http);
    http.listen(0, "127.0.0.1");
    await once(http, "listening");

    const environment = {
      PATH: process.env.PATH, HOME: home, TMPDIR: join(root, "tmp"),
      XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"),
      XDG_DATA_HOME: join(root, "data"), XDG_CONFIG_HOME: join(root, "config"),
      XDG_RUNTIME_DIR: runtime, SSH_AUTH_SOCK: permitted[0], PI_NVIM_SOCKET: neovim,
      PI_NVIM_BROKER: broker, PI_NVIM_LAUNCH_ID: launchId, NO_COLOR: "1",
    };
    const args = launchArguments(work, join(home, ".pi", "agent"), home, environment,
      profilePath, process.execPath, process.env.ENV_TEST_BINARY ?? "/usr/bin/env");
    const boundary = args.indexOf("--");
    const grants = args.slice(0, boundary);
    assert.deepEqual(grants.flatMap((part, index) => part === "--allow-unix-socket" ? [grants[index + 1]] : []), permitted);
    assert.ok(grants.some((part, index) => part === "--allow" && grants[index + 1] === runtime));
    const result = await run(process.env.NONO_TEST_BINARY, [
      ...grants, "--read", dirname(probe), "--open-port", String(http.address().port),
      "--no-audit", "--no-rollback", ...args.slice(boundary),
      probe, JSON.stringify({ sockets, permitted, bindPath: join(runtime, "new.sock"), url: `http://127.0.0.1:${http.address().port}` }),
    ], { cwd: work, env: environment }, { signal: t.signal });
    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.code, 0, result.stderr || result.stdout);
    const report = JSON.parse(result.stdout.trim());
    assert.deepEqual(report.denied, sockets);
    assert.deepEqual(report.connected, permitted);
    assert.equal(report.bindDenied, true);
    assert.equal(report.stdio, "stdio-fixture");
    assert.equal(report.http, "http-fixture");
    assert.equal(accepted, baseline + permitted.length, "only explicitly permitted connections may reach a listener");
  } finally {
    for (const socket of connections) socket.destroy();
    for (const server of servers) server.closeAllConnections?.();
    await Promise.all(servers.map((server) => new Promise((resolve) => server.close(resolve))));
    rmSync(root, { recursive: true, force: true });
  }
});
