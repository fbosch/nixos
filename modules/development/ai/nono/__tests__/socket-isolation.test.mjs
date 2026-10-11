import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync } from "node:fs";
import { createServer as createHttpServer } from "node:http";
import { createConnection, createServer } from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";

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

test("nono denies host-style sockets and aliases while stdio and HTTP MCP initialize", {
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
    for (const path of [
      work, join(work, "podman"), join(work, "systemd"), join(home, ".pi"),
      join(home, ".npm", "_cacache"), join(home, ".npm", "_logs"),
      join(root, "tmp"), join(root, "state"), join(root, "cache"), join(root, "data"), join(root, "config"),
    ]) mkdirSync(path, { recursive: true });

    const sockets = [
      join(work, "podman", "podman.sock"),
      join(work, "docker.sock"),
      join(work, "systemd", "private"),
      join(work, "bus"),
    ];
    let accepted = 0;
    for (const path of sockets) {
      const server = createServer((socket) => {
        accepted++;
        connections.add(socket);
        socket.once("close", () => connections.delete(socket));
        socket.end();
      });
      servers.push(server);
      server.listen(path);
      await once(server, "listening");
      const connection = createConnection(path);
      await once(connection, "connect");
      connection.destroy();
    }
    const alias = join(work, "alias.sock");
    symlinkSync(sockets[0], alias);
    sockets.push(alias);
    assert.equal(accepted, 4, "fixture sockets must be reachable before confinement");

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

    const result = await run(process.env.NONO_TEST_BINARY, [
      "run", "--profile", profilePath, "--allow-cwd", "--read", dirname(probe),
      "--no-audit", "--no-rollback", "--suppress-save-prompt", "/", "--",
      process.execPath, probe, JSON.stringify({ sockets, url: `http://127.0.0.1:${http.address().port}` }),
    ], {
      cwd: work,
      env: {
        PATH: process.env.PATH, HOME: home, TMPDIR: join(root, "tmp"),
        XDG_STATE_HOME: join(root, "state"), XDG_CACHE_HOME: join(root, "cache"),
        XDG_DATA_HOME: join(root, "data"), XDG_CONFIG_HOME: join(root, "config"),
        XDG_RUNTIME_DIR: work, NO_COLOR: "1",
      },
    }, { signal: t.signal });
    assert.equal(result.signal, null, result.stderr);
    assert.equal(result.code, 0, result.stderr || result.stdout);
    const report = JSON.parse(result.stdout.trim());
    assert.deepEqual(report.denied, sockets);
    assert.equal(report.stdio, "stdio-fixture");
    assert.equal(report.http, "http-fixture");
    assert.equal(accepted, 4, "sandbox must not reach any fixture control socket");
  } finally {
    for (const socket of connections) socket.destroy();
    for (const server of servers) server.closeAllConnections?.();
    await Promise.all(servers.map((server) => new Promise((resolve) => server.close(resolve))));
    rmSync(root, { recursive: true, force: true });
  }
});
