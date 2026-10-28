import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, watch } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { runWithCredentialProxy } from "../scripts/credential-proxy.mjs";
import { proxyFixtureSource } from "./fixtures/credential-proxy.mjs";

function fixture(options = {}) {
  const root = mkdtempSync(join(tmpdir(), "pi-credential-proxy-"));
  const nono = join(root, "nono");
  const profile = join(root, "profile.json");
  const pidFile = join(root, "proxy.pid");
  const recordFile = join(root, "capture.json");
  const output = join(root, "pi.json");
  const bundle = join(root, "bundle.pem");
  writeFileSync(bundle, "fixture public CA bundle");
  writeFileSync(nono, `#!${process.execPath}\n${proxyFixtureSource({ pidFile, recordFile, ...options, trustBundle: bundle })}`, { mode: 0o700 });
  writeFileSync(profile, JSON.stringify({
    network: { credentials: ["context7"], custom_credentials: {
      context7: { upstream: "http://127.0.0.1:1", env_var: "CONTEXT7_API_KEY" },
    }, tls_intercept: { ca_env_vars: ["EXTRA_CA"] } },
  }));
  const environment = {
    HOME: root, PATH: process.env.PATH, GH_CONFIG_DIR: join(root, ".config", "gh"),
    BASH_ENV: "/untrusted/preload", NODE_OPTIONS: "--trace-warnings",
    NO_PROXY: "*", no_proxy: "mcp.context7.com", ALL_PROXY: "http://untrusted",
    OTHER: "kept",
  };
  const checkStopped = () => {
    if (existsSync(pidFile)) assert.throws(() => process.kill(Number(readFileSync(pidFile, "utf8")), 0), { code: "ESRCH" });
  };
  return { root, nono, profile, pidFile, recordFile, output, bundle, environment, checkStopped };
}

test("unsandboxed Pi receives proxy credentials only after a complete startup handoff", async () => {
  const f = fixture({ splitStartup: true });
  try {
    const result = await runWithCredentialProxy(f.nono, f.profile, [process.execPath, "-e", `
      const fs = require("node:fs");
      fs.writeFileSync(${JSON.stringify(f.output)}, JSON.stringify(process.env));
      fs.writeFileSync(${JSON.stringify(join(f.root, "ordinary-write"))}, "unconfined");
      process.exit(17);
    `], f.environment);
    assert.equal(result.status, 17);
    const actual = JSON.parse(readFileSync(f.output, "utf8"));
    const host = JSON.parse(readFileSync(f.recordFile, "utf8"));
    assert.equal(actual.CONTEXT7_API_KEY, host.token);
    assert.equal(actual.NONO_PROXY_TOKEN, host.token);
    assert.equal(actual.HTTP_PROXY, actual.HTTPS_PROXY);
    assert.equal(new URL(actual.HTTPS_PROXY).password, host.token);
    assert.equal(actual.NO_PROXY, "localhost,127.0.0.1,::1");
    assert.equal(actual.NODE_USE_ENV_PROXY, "1");
    assert.equal(actual.NODE_OPTIONS, "--disable-warning=UNDICI-EHPA");
    assert.equal(actual.SSL_CERT_FILE, f.bundle);
    assert.equal(actual.NODE_EXTRA_CA_CERTS, f.bundle);
    assert.equal(actual.EXTRA_CA, f.bundle);
    assert.equal(actual.OTHER, "kept");
    assert.equal(actual.GH_CONFIG_DIR, f.environment.GH_CONFIG_DIR);
    assert.equal(host.ghConfig, f.environment.GH_CONFIG_DIR);
    assert.equal(host.nodeOptions, undefined);
    assert.equal(host.bashEnv, undefined);
    assert.equal(host.contextKey, undefined);
    assert.deepEqual(host.args.slice(0, 3), ["proxy", "--profile", f.profile]);
    assert.equal(host.args.includes("run"), false);
    assert.equal(actual.NONO_PROXY_PASS, undefined);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

for (const [options, message] of [
  [{ fail: true }, /exited before readiness/],
  [{ invalidHost: true }, /Invalid Nono proxy startup/],
  [{ noReady: true }, /Timed out/],
]) {
  test(`proxy startup fails closed: ${JSON.stringify(options)}`, async () => {
    const f = fixture(options);
    try {
      await assert.rejects(runWithCredentialProxy(f.nono, f.profile, [process.execPath, "-e", `require("node:fs").writeFileSync(${JSON.stringify(f.output)}, "must not start")`], f.environment, { startupTimeout: 500, shutdownTimeout: 200 }), message);
      assert.equal(existsSync(f.output), false);
      f.checkStopped();
    } finally { rmSync(f.root, { recursive: true, force: true }); }
  });
}

test("an additional MCP route gets its declared placeholder and base URL", async () => {
  const f = fixture();
  try {
    writeFileSync(f.profile, JSON.stringify({
      network: {
        credentials: ["docs"],
        custom_credentials: {
          docs: { upstream: "https://docs.example.test", env_var: "DOCS_API_KEY", inject_header: "x-api-key", credential_format: "{}" },
        },
      },
    }));
    const result = await runWithCredentialProxy(f.nono, f.profile, [process.execPath, "-e", `
      require("node:fs").writeFileSync(${JSON.stringify(f.output)}, JSON.stringify({
        key: process.env.DOCS_API_KEY,
        base: process.env.DOCS_BASE_URL,
        tokenMatches: process.env.DOCS_API_KEY === process.env.NONO_PROXY_TOKEN,
      }));
    `], f.environment);
    assert.equal(result.status, 0);
    const actual = JSON.parse(readFileSync(f.output, "utf8"));
    assert.equal(actual.key, JSON.parse(readFileSync(f.recordFile, "utf8")).token);
    assert.equal(actual.tokenMatches, true);
    assert.equal(new URL(actual.base).pathname, "/docs");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("proxy cleanup also runs when Pi cannot spawn or ignores proxy shutdown", async () => {
  const f = fixture({ ignoreInterrupt: true });
  try {
    const result = await runWithCredentialProxy(f.nono, f.profile, [join(f.root, "missing-pi")], f.environment, { shutdownTimeout: 100 });
    assert.equal(result.error.code, "ENOENT");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("proxy failure terminates the active Pi session instead of falling back to direct traffic", async () => {
  const f = fixture({ exitAfterReady: true });
  try {
    await assert.rejects(runWithCredentialProxy(f.nono, f.profile, [process.execPath, "-e", "setInterval(() => {}, 1000)"], f.environment, { shutdownTimeout: 100 }), /stopped while Pi was running/);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("a terminated Pi preserves its signal and leaves no proxy", async () => {
  const f = fixture();
  try {
    const result = await runWithCredentialProxy(f.nono, f.profile, [process.execPath, "-e", 'process.kill(process.pid, "SIGTERM")'], f.environment);
    assert.equal(result.signal, "SIGTERM");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("the full --no-sandbox launcher forwards termination and cleans up its proxy", async () => {
  const f = fixture();
  try {
    const agent = join(f.root, ".pi", "agent");
    mkdirSync(agent, { recursive: true });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const child = spawn(process.execPath, [launcher, f.nono, process.execPath, f.profile, "/missing-direnv", "/missing-env", "--no-sandbox", "-e", 'console.log("pi-ready");setInterval(() => {}, 1000)'], {
      env: { HOME: f.root, PATH: process.env.PATH, PI_CODING_AGENT_DIR: agent }, stdio: ["ignore", "pipe", "pipe"],
    });
    let diagnostics = "";
    child.stderr.on("data", (chunk) => { diagnostics += chunk; });
    const exited = once(child, "exit");
    await once(child.stdout, "data");
    child.kill("SIGTERM");
    const [status, signal] = await exited;
    assert.equal(status, null, diagnostics);
    assert.equal(signal, "SIGTERM", diagnostics);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("termination during startup preserves the signal and removes the pending proxy", { timeout: 5000 }, async () => {
  const f = fixture({ noReady: true });
  const watcher = watch(f.root);
  try {
    const created = new Promise((resolve) => {
      watcher.on("change", (_, name) => { if (name === "proxy.pid") resolve(); });
    });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mjs", import.meta.url));
    const child = spawn(process.execPath, [launcher, f.nono, process.execPath, f.profile, "/missing-direnv", "/missing-env", "--no-sandbox", "-e", "throw new Error('must not start')"], {
      env: { HOME: f.root, PATH: process.env.PATH }, stdio: "ignore",
    });
    const exited = once(child, "exit");
    await created;
    child.kill("SIGTERM");
    const [status, signal] = await exited;
    assert.equal(status, null);
    assert.equal(signal, "SIGTERM");
    f.checkStopped();
  } finally {
    watcher.close();
    rmSync(f.root, { recursive: true, force: true });
  }
});

test("installed Nono uses the packaged Context7 capture command and forwards an event stream", {
  skip: !process.env.NONO_PROXY_TEST_BINARY || !process.env.NONO_TEST_PROFILE,
  timeout: 15_000,
}, async () => {
  const f = fixture();
  let finishStream;
  const upstream = createServer((request, response) => {
    if (request.url === "/ack") {
      finishStream();
      response.end("ack");
      return;
    }
    assert.equal(request.headers.authorization, "Bearer fixture-upstream-secret");
    response.writeHead(200, { "content-type": "text/event-stream" });
    response.write("data: first\n\n");
    finishStream = () => response.end("data: last\n\n");
  });
  try {
    upstream.listen(0, "127.0.0.1");
    await once(upstream, "listening");
    const secret = join(f.root, "synthetic-context7-key");
    writeFileSync(secret, "fixture-upstream-secret", { mode: 0o400 });
    const template = JSON.parse(readFileSync(process.env.NONO_TEST_PROFILE, "utf8"));
    const captureCommand = [...template.credential_capture.context7.command.slice(0, -1), secret];
    writeFileSync(f.profile, JSON.stringify({
      network: { credentials: ["context7"], custom_credentials: {
        context7: { upstream: `http://127.0.0.1:${upstream.address().port}`, credential_key: "cmd://context7", env_var: "CONTEXT7_API_KEY" },
      } },
      credential_capture: { context7: { command: captureCommand } },
    }));
    const result = await runWithCredentialProxy(process.env.NONO_PROXY_TEST_BINARY, f.profile, [process.execPath, "-e", `
      (async () => {
        const response = await fetch(process.env.CONTEXT7_BASE_URL + "/mcp", {
          headers: { Authorization: "Bearer " + process.env.CONTEXT7_API_KEY },
          signal: AbortSignal.timeout(3000),
        });
        const reader = response.body.getReader();
        const first = new TextDecoder().decode((await reader.read()).value);
        if (!response.ok || !first.includes("data: first") || first.includes("data: last")) process.exit(1);
        // The upstream cannot end until this acknowledgement: proves incremental delivery.
        await fetch(${JSON.stringify("http://127.0.0.1:")} + ${upstream.address().port} + "/ack");
        let rest = "";
        for (;;) {
          const chunk = await reader.read();
          if (chunk.done) break;
          rest += new TextDecoder().decode(chunk.value);
        }
        if (!rest.includes("data: last") || (first + rest).includes("fixture-upstream-secret")) process.exit(1);
      })().catch(() => process.exit(1));
    `], { HOME: f.root, PATH: process.env.PATH }, { platform: "linux" });
    assert.equal(result.status, 0);
  } finally {
    upstream.closeAllConnections();
    await new Promise((resolve) => upstream.close(resolve));
    rmSync(f.root, { recursive: true, force: true });
  }
});
