import { spawn } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import { stripVTControlCharacters } from "node:util";

const caVariables = ["SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS", "REQUESTS_CA_BUNDLE", "CURL_CA_BUNDLE", "GIT_SSL_CAINFO"];
const signals = ["SIGINT", "SIGTERM", "SIGHUP"];

function exitOf(child) {
  return new Promise((resolve) => {
    child.once("error", (error) => resolve({ error, status: null, signal: null }));
    child.once("exit", (status, signal) => resolve({ status, signal }));
  });
}

function signalGroup(child, signal) {
  if (!child.pid) return;
  try {
    process.kill(-child.pid, signal);
  } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
}

async function stopProxy(proxy, exited, timeout) {
  signalGroup(proxy, "SIGINT");
  const timer = setTimeout(() => signalGroup(proxy, "SIGKILL"), timeout);
  try {
    await exited;
  } finally {
    clearTimeout(timer);
    // A capture helper may outlive the proxy leader; remove the owned group too.
    signalGroup(proxy, "SIGKILL");
  }
}

function clientEnvironment(environment, profile, token, connection) {
  const proxyUrl = `http://nono:${token}@127.0.0.1:${connection.port}`; // pragma: allowlist secret -- token is generated at runtime.
  const local = "localhost,127.0.0.1,::1";
  const result = {
    ...environment,
    HTTP_PROXY: proxyUrl, HTTPS_PROXY: proxyUrl,
    http_proxy: proxyUrl, https_proxy: proxyUrl,
    NO_PROXY: local, no_proxy: local,
    NONO_PROXY_TOKEN: token,
    NODE_USE_ENV_PROXY: "1",
    NODE_OPTIONS: "--disable-warning=UNDICI-EHPA",
  };
  // Inherited bypasses must not send phantom credentials directly to an upstream.
  delete result.ALL_PROXY;
  delete result.all_proxy;
  for (const name of profile.network?.credentials ?? []) {
    const route = profile.network?.custom_credentials?.[name];
    if (!route || typeof route.env_var !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(route.env_var) ||
        !/^[A-Za-z0-9_]+$/.test(name)) {
      throw new Error(`Standalone Pi proxy requires an explicit custom credential route for ${name}`);
    }
    result[route.env_var] = token;
    result[`${name.toUpperCase()}_BASE_URL`] = `http://127.0.0.1:${connection.port}/${name}`;
  }
  if (connection.trustBundle) {
    for (const name of [...caVariables, ...(profile.network?.tls_intercept?.ca_env_vars ?? [])]) {
      result[name] = connection.trustBundle;
    }
  }
  return result;
}

function connectionReader(proxy, token, timeout) {
  let rejectReady;
  let settled = false;
  let pending = "";
  let connection;
  let trustBundle;
  const ready = new Promise((resolve, reject) => {
    rejectReady = reject;
    // shortcut: Nono 0.80 has no machine-readable handoff. Parse documented startup
    // lines without evaluating exports; replace this when Nono exposes structured output.
    proxy.stdout.setEncoding("utf8");
    proxy.stdout.on("data", (chunk) => {
      if (settled) return;
      pending += chunk;
      if (pending.length > 65536) return fail(new Error("Nono proxy startup output exceeded its limit"));
      for (;;) {
        const end = pending.indexOf("\n");
        if (end === -1) break;
        const line = stripVTControlCharacters(pending.slice(0, end)).trim();
        pending = pending.slice(end + 1);
        try {
          if (line.startsWith("proxy URL: ")) {
            const url = new URL(line.slice("proxy URL: ".length));
            if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || url.username !== "nono" ||
                url.password !== token || url.pathname !== "/" || url.search || url.hash || !url.port) {
              throw new Error("Invalid Nono proxy connection details");
            }
            connection = { port: Number(url.port) };
          } else if (line.startsWith("TLS interception trust bundle: ")) {
            trustBundle = line.slice("TLS interception trust bundle: ".length);
            if (!isAbsolute(trustBundle) || !statSync(trustBundle).isFile()) {
              throw new Error("Invalid Nono proxy trust bundle");
            }
          } else if (line === "Press Ctrl-C to stop.") {
            if (!connection) throw new Error("Nono proxy did not publish authenticated connection details");
            settled = true;
            resolve({ ...connection, trustBundle });
          }
        } catch {
          fail(new Error("Invalid Nono proxy startup handoff"));
          return;
        }
      }
    });
  });
  const timer = setTimeout(() => fail(new Error("Timed out waiting for Nono credential proxy")), timeout);
  function fail(error) {
    if (settled) return;
    settled = true;
    rejectReady(error);
  }
  return { ready, fail, dispose: () => clearTimeout(timer) };
}

export async function runWithCredentialProxy(nono, profilePath, command, environment, {
  startupTimeout = 30_000,
  shutdownTimeout = 2_000,
  platform = process.platform,
} = {}) {
  if (!isAbsolute(nono) || !existsSync(nono)) throw new Error(`nono executable missing: ${nono}`);
  if (!isAbsolute(profilePath) || !existsSync(profilePath) || !statSync(profilePath).isFile()) throw new Error("Nix nono profile missing");
  const profile = JSON.parse(readFileSync(profilePath, "utf8"));
  const token = randomBytes(32).toString("hex");
  const proxyEnvironment = { ...environment, NONO_PROXY_PASS: token, NO_COLOR: "1", CLICOLOR: "0" };
  for (const name of ["NODE_OPTIONS", "NODE_PATH", "BASH_ENV", "ENV"]) delete proxyEnvironment[name];
  const proxy = spawn(nono, [
    "proxy", "--profile", profilePath, "--listen", "127.0.0.1", "--port", "0",
    ...(platform === "darwin" ? ["--trust-proxy-ca"] : []),
  ], { env: proxyEnvironment, stdio: ["ignore", "pipe", "pipe"], detached: true });
  const proxyExited = exitOf(proxy);
  // Never relay startup stdout: it contains the session's broker credentials.
  let diagnostics = "";
  proxy.stderr.setEncoding("utf8");
  proxy.stderr.on("data", (chunk) => {
    diagnostics = (diagnostics + chunk).slice(-8192);
  });
  const reader = connectionReader(proxy, token, startupTimeout);
  let child;
  let requestedSignal;
  let childStopTimer;
  const handlers = new Map(signals.map((signal) => [signal, () => {
    // A terminal sends SIGINT to the foreground group, including Pi already.
    if (signal === "SIGINT" && child && process.stdin.isTTY) return;
    requestedSignal = signal;
    if (child) {
      child.kill(signal);
      childStopTimer ??= setTimeout(() => child.kill("SIGKILL"), shutdownTimeout);
    } else reader.fail(new Error(`Pi launch interrupted by ${signal}`));
  }]));
  for (const [signal, handler] of handlers) process.on(signal, handler);
  try {
    const startupExit = proxyExited.then((result) => {
      throw new Error(result.error ? "Nono credential proxy could not start" :
        `Nono credential proxy exited before readiness (status ${result.status}, signal ${result.signal})`);
    });
    const connection = await Promise.race([reader.ready, startupExit]);
    reader.dispose();
    if (requestedSignal) return { status: null, signal: requestedSignal };
    const childEnvironment = clientEnvironment(environment, profile, token, connection);
    child = spawn(command[0], command.slice(1), { stdio: "inherit", env: childEnvironment });
    const childExited = exitOf(child);
    const result = await Promise.race([
      childExited.then((result) => ({ kind: "child", result })),
      proxyExited.then((result) => ({ kind: "proxy", result })),
    ]);
    if (result.kind === "proxy") {
      child.kill("SIGTERM");
      const timer = setTimeout(() => child.kill("SIGKILL"), shutdownTimeout);
      try { await childExited; } finally { clearTimeout(timer); }
      throw new Error("Nono credential proxy stopped while Pi was running");
    }
    return requestedSignal ? { ...result.result, signal: requestedSignal, status: null } : result.result;
  } catch (error) {
    if (requestedSignal) return { status: null, signal: requestedSignal };
    const safeDiagnostics = stripVTControlCharacters(diagnostics).replaceAll(token, "[broker token]").trim();
    if (safeDiagnostics) console.error(safeDiagnostics);
    throw error;
  } finally {
    reader.dispose();
    clearTimeout(childStopTimer);
    await stopProxy(proxy, proxyExited, shutdownTimeout);
    for (const [signal, handler] of handlers) process.off(signal, handler);
  }
}
