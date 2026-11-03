import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, watch } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { credentialProxySession } from "../scripts/credentials/proxy.mts";
import { proxyFixtureSource } from "./fixtures/credential-proxy.mjs";
import * as Effect from "effect/Effect";

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
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", `
      const fs = require("node:fs");
      fs.writeFileSync(${JSON.stringify(f.output)}, JSON.stringify(process.env));
      fs.writeFileSync(${JSON.stringify(join(f.root, "ordinary-write"))}, "unconfined");
      process.exit(17);
    `], f.environment));
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

test("Claude placeholder and base URL replace inherited routing without exposing a login token", async () => {
  const f = fixture();
  writeFileSync(f.profile, JSON.stringify({network:{credentials:["anthropic"],custom_credentials:{
    anthropic:{upstream:"https://api.anthropic.com",env_var:"CLAUDE_CODE_OAUTH_TOKEN",inject_header:"Authorization",credential_format:"Bearer {}"},
  }}}));
  try {
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", `require("node:fs").writeFileSync(${JSON.stringify(f.output)},JSON.stringify(process.env))`], {
      ...f.environment, ANTHROPIC_BASE_URL:"https://untrusted.invalid",
    }));
    assert.equal(result.status,0);
    const child = JSON.parse(readFileSync(f.output,"utf8"));
    const proxy = JSON.parse(readFileSync(f.recordFile,"utf8"));
    assert.equal(child.CLAUDE_CODE_OAUTH_TOKEN,proxy.token);
    const base = new URL(child.ANTHROPIC_BASE_URL);
    assert.equal(base.protocol,"http:");
    assert.equal(base.hostname,"127.0.0.1");
    assert.equal(base.port,new URL(child.HTTP_PROXY).port);
    assert.equal(base.pathname,"/anthropic");
    assert.equal(child.NONO_PROXY_PASS,undefined);
    f.checkStopped();
  } finally { rmSync(f.root,{recursive:true,force:true}); }
});
for (const [options, message] of [
  [{ fail: true }, /exited before readiness/],
  [{ invalidHost: true }, /Invalid Nono proxy startup/],
  [{ noReady: true }, /Timed out/],
]) {
  test(`proxy startup fails closed: ${JSON.stringify(options)}`, async () => {
    const f = fixture(options);
    // Only noReady tests the deadline; error fixtures need startup headroom under parallel builds.
    const startupTimeout = options.noReady ? 500 : 5000;
    try {
      await assert.rejects(Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", `require("node:fs").writeFileSync(${JSON.stringify(f.output)}, "must not start")`], f.environment, { startupTimeout, shutdownTimeout: 200 })), message);
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
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", `
      require("node:fs").writeFileSync(${JSON.stringify(f.output)}, JSON.stringify({
        key: process.env.DOCS_API_KEY,
        base: process.env.DOCS_BASE_URL,
        tokenMatches: process.env.DOCS_API_KEY === process.env.NONO_PROXY_TOKEN,
      }));
    `], f.environment));
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
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, [join(f.root, "missing-pi")], f.environment, { shutdownTimeout: 100 }));
    assert.equal(result.error.code, "ENOENT");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("proxy failure terminates the active Pi session instead of falling back to direct traffic", async () => {
  const f = fixture({ exitAfterReady: true });
  try {
    await assert.rejects(Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", "setInterval(() => {}, 1000)"], f.environment, { shutdownTimeout: 100 })), /stopped while Pi was running/);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("a terminated Pi preserves its signal and leaves no proxy", async () => {
  const f = fixture();
  try {
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", 'process.kill(process.pid, "SIGTERM")'], f.environment));
    assert.equal(result.signal, "SIGTERM");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("raw launch replaces the bootstrap so termination reaches Pi directly", async () => {
  const f = fixture();
  try {
    const agent = join(f.root, ".pi", "agent");
    mkdirSync(agent, { recursive: true });
    const launcher = fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url));
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
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("termination during startup preserves the signal and removes the pending proxy", { timeout: 5000 }, async () => {
  const f = fixture({ noReady: true });
  const watcher = watch(f.root);
  try {
    const created = new Promise((resolve) => {
      watcher.on("change", (_, name) => { if (name === "proxy.pid") resolve(); });
    });
    const proxyModule = new URL("../scripts/credentials/proxy.mts", import.meta.url).href;
    const script = `
      import { credentialProxySession } from ${JSON.stringify(proxyModule)}; import * as Effect from ${JSON.stringify(import.meta.resolve("effect/Effect"))};
      const result = await Effect.runPromise(credentialProxySession(${JSON.stringify(f.nono)}, ${JSON.stringify(f.profile)},
        [process.execPath, "-e", "throw new Error('must not start')"], process.env));
      if (result.signal) process.kill(process.pid, result.signal);
      process.exit(result.status ?? 1);
    `;
    const child = spawn(process.execPath, ["--input-type=module", "-e", script], {
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

for (const name of ["context7", "exa", "exa_mcp"]) {
  test(`installed Nono captures ${name}, injects its header, and forwards an event stream`, {
    skip: !process.env.NONO_PROXY_TEST_BINARY || !process.env.NONO_TEST_PROFILE,
    timeout: 15_000,
  }, async () => {
    const f = fixture();
    const template = JSON.parse(readFileSync(process.env.NONO_TEST_PROFILE, "utf8"));
    const route = template.network.custom_credentials[name];
    const header = route.inject_header;
    const names = name.startsWith("exa") ? ["exa", "exa_mcp"] : [name];
    const requestPath = name === "exa" ? "/search" : "/mcp";
    let finishStream;
    const upstream = createServer((request, response) => {
      if (request.url === "/ack") {
        finishStream();
        response.end("ack");
        return;
      }
      assert.equal(request.method, "POST");
      assert.equal(request.url, requestPath);
      assert.equal(request.headers[header.toLowerCase()], route.credential_format.replace("{}", "fixture-upstream-secret"));
      response.writeHead(200, { "content-type": "text/event-stream" });
      response.write("data: first\n\n");
      finishStream = () => response.end("data: last\n\n");
    });
    try {
      upstream.listen(0, "127.0.0.1");
      await once(upstream, "listening");
      const secret = join(f.root, "synthetic-credential");
      writeFileSync(secret, "fixture-upstream-secret", { mode: 0o400 });
      writeFileSync(f.profile, JSON.stringify({
        // The supervisor must capture this file even though the child's policy denies it.
        filesystem: { deny: [secret] },
        network: {
          credentials: names,
          custom_credentials: Object.fromEntries(names.map((service) => [service, {
            ...template.network.custom_credentials[service],
            upstream: `http://127.0.0.1:${upstream.address().port}`,
          }])),
        },
        credential_capture: Object.fromEntries(names.map((service) => [service, {
          command: [...template.credential_capture[service].command.slice(0, -1), secret],
        }])),
      }));
      const result = await Effect.runPromise(credentialProxySession(process.env.NONO_PROXY_TEST_BINARY, f.profile, [process.execPath, "-e", `
        (async () => {
          const response = await fetch(process.env[${JSON.stringify(name.toUpperCase() + "_BASE_URL")}] + ${JSON.stringify(requestPath)}, {
            method: "POST", body: JSON.stringify({ query: "synthetic search" }),
            headers: { [${JSON.stringify(header)}]: ${JSON.stringify(route.credential_format)}.replace("{}", process.env[${JSON.stringify(route.env_var)}]) },
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
      `], { HOME: f.root, PATH: process.env.PATH }, { platform: "linux" }));
      assert.equal(result.status, 0);
    } finally {
      upstream.closeAllConnections();
      await new Promise((resolve) => upstream.close(resolve));
      rmSync(f.root, { recursive: true, force: true });
    }
  });
}

test("sandbox proxy retains filesystem policy and grants only its port and public trust bundle", async () => {
  const f = fixture();
  const original = {
    ...JSON.parse(readFileSync(f.profile, "utf8")),
    extends: "default",
    filesystem: { deny: [join(f.root, "host-secret")] },
    linux: { af_unix_mediation: "pathname", sandbox_policy: "landlock" },
    security: { capability_elevation: false },
    credential_capture: { context7: { command: ["/synthetic/capture"] } },
  };
  original.network.open_port = [9222];
  writeFileSync(f.profile, JSON.stringify(original));
  writeFileSync(f.nono, `#!${process.execPath}
    if (process.argv[2] === "run") {
      const fs = require("node:fs");
      const args = process.argv.slice(2);
      const profilePath = args[args.indexOf("--profile") + 1];
      const bundle = process.env.SSL_CERT_FILE;
      fs.writeFileSync(${JSON.stringify(f.output)}, JSON.stringify({
        args, profilePath, profile: JSON.parse(fs.readFileSync(profilePath, "utf8")),
        bundle, bundleContents: fs.readFileSync(bundle, "utf8"), extraCa: process.env.EXTRA_CA,
        proxyPort: new URL(process.env.HTTP_PROXY).port,
        token: process.env.CONTEXT7_API_KEY, brokerPassword: process.env.NONO_PROXY_PASS,
      }));
      process.exit(17);
    }
    ${proxyFixtureSource({ pidFile: f.pidFile, recordFile: f.recordFile, trustBundle: f.bundle })}
  `, { mode: 0o700 });
  const command = [f.nono, "run", "--profile", f.profile, "--allow-connect-port", "443", "--", process.execPath, "-e", "throw new Error('fixture must handle sandbox')"];
  try {
    const result = await Effect.runPromise(credentialProxySession(f.nono, f.profile, command, { HOME: f.root, PATH: process.env.PATH, TMPDIR: f.root }, { sandboxed: true, platform: "linux" }));
    assert.equal(result.status, 17);
    const actual = JSON.parse(readFileSync(f.output, "utf8"));
    assert.deepEqual(actual.profile.filesystem, original.filesystem);
    assert.deepEqual(actual.profile.linux, original.linux);
    assert.deepEqual(actual.profile.security, original.security);
    assert.deepEqual(actual.profile.network, { block: true, credentials: [], network_profile: null, open_port: [9222] });
    assert.deepEqual(actual.profile.credential_capture, {});
    // The fixture command omits --allow-cwd, as the launcher does when it splits the working directory itself.
    assert.deepEqual(actual.profile.workdir, { access: "none" });
    assert.deepEqual(actual.args.slice(actual.args.indexOf("--") - 4, actual.args.indexOf("--")), ["--allow-connect-port", actual.proxyPort, "--read-file", actual.bundle]);
    assert.equal(actual.bundleContents, "fixture public CA bundle");
    assert.equal(actual.extraCa, actual.bundle);
    assert.notEqual(actual.bundle, f.bundle);
    assert.equal(actual.token, JSON.parse(readFileSync(f.recordFile, "utf8")).token);
    assert.equal(actual.brokerPassword, undefined);
    assert.equal(existsSync(actual.profilePath), false);
    assert.equal(existsSync(actual.bundle), false);
    assert.deepEqual(JSON.parse(readFileSync(f.profile, "utf8")), original);
    assert.equal(command[command.indexOf("--profile") + 1], f.profile);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("sandbox proxy rejects an unconfined child instead of falling back", async () => {
  const f = fixture();
  try {
    await assert.rejects(Effect.runPromise(credentialProxySession(f.nono, f.profile, [process.execPath, "-e", `require('node:fs').writeFileSync(${JSON.stringify(f.output)}, 'unconfined')`],
      { HOME: f.root, PATH: process.env.PATH, TMPDIR: f.root }, { sandboxed: true, platform: "linux" })), /requires a profiled nono run command/);
    assert.equal(existsSync(f.output), false);
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("Linux launcher selects the standalone proxy without bypassing nono run", { skip: process.platform !== "linux" }, async () => {
  const f = fixture();
  const home = join(f.root, "home");
  const work = join(f.root, "work");
  const temporary = join(f.root, "tmp");
  const agent = join(home, ".pi", "agent");
  for (const directory of [agent, work, temporary]) mkdirSync(directory, { recursive: true });
  writeFileSync(f.nono, `#!${process.execPath}
    if (process.argv[2] === "run") {
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      const args = process.argv.slice(2);
      const profile = JSON.parse(fs.readFileSync(args[args.indexOf("--profile") + 1], "utf8"));
      assert.equal(profile.network.block, true);
      assert.deepEqual(profile.network.credentials, []);
      assert.deepEqual(profile.credential_capture, {});
      assert.equal(args[args.indexOf("--") + 1], ${JSON.stringify(process.env.ENV_TEST_BINARY ?? "/usr/bin/env")});
      assert.equal(typeof process.env.CONTEXT7_API_KEY, "string");
      assert.ok(args.includes(new URL(process.env.HTTP_PROXY).port));
      fs.writeFileSync(${JSON.stringify(f.output)}, "sandbox started");
      process.exit(17);
    }
    ${proxyFixtureSource({ pidFile: f.pidFile })}
  `, { mode: 0o700 });
  try {
    const launcher = fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url));
    // Proxy plumbing only; model-executor-launch.test.mjs covers the executor default and fail-closed setup.
    const child = spawn(process.execPath, [launcher, f.nono, process.execPath, f.profile, "/missing-direnv", process.env.ENV_TEST_BINARY ?? "/usr/bin/env", "--version"], {
      cwd: work, env: { HOME: home, PATH: process.env.PATH, TMPDIR: temporary, PI_CODING_AGENT_DIR: agent, PI_MODEL_EXECUTOR: "0" }, stdio: ["ignore", "pipe", "pipe"],
    });
    const exited = once(child, "exit");
    let stderr = "";
    child.stdout.resume();
    child.stderr.on("data", chunk => stderr += chunk);
    const [status, signal] = await exited;
    assert.equal(signal, null, stderr);
    assert.equal(status, 17, stderr);
    assert.equal(readFileSync(f.output, "utf8"), "sandbox started");
    f.checkStopped();
  } finally { rmSync(f.root, { recursive: true, force: true }); }
});

test("installed Nono standalone proxy injects credentials while its child remains sandboxed", {
  skip: process.platform !== "linux" || !process.env.NONO_PROXY_TEST_BINARY,
  timeout: 15000,
}, async () => {
  const f = fixture();
  const work = join(f.root, "work");
  const home = join(f.root, "home");
  const temporary = join(f.root, "tmp");
  const secret = join(f.root, "credential");
  const denied = join(f.root, "host-secret");
  for (const directory of [work, home, temporary]) mkdirSync(directory);
  writeFileSync(secret, "fixture-upstream-secret", { mode: 0o400 });
  writeFileSync(denied, "synthetic-host-secret", { mode: 0o400 });
  const upstream = createServer((request, response) => {
    assert.equal(request.headers.authorization, "Bearer fixture-upstream-secret");
    response.end("ok");
  });
  try {
    upstream.listen(0, "127.0.0.1");
    await once(upstream, "listening");
    writeFileSync(f.profile, JSON.stringify({
      extends: "default",
      filesystem: { read: ["/nix/store"], deny: [secret, denied] },
      linux: { af_unix_mediation: "pathname", sandbox_policy: "landlock" },
      network: { credentials: ["context7"], custom_credentials: {
        context7: { upstream: `http://127.0.0.1:${upstream.address().port}`, credential_key: "cmd://context7", env_var: "CONTEXT7_API_KEY", inject_header: "Authorization", credential_format: "Bearer {}" },
      } },
      credential_capture: { context7: { command: [process.execPath, "-e", `process.stdout.write(require('node:fs').readFileSync(${JSON.stringify(secret)}))`] } },
    }));
    const probe = `
      const assert = require("node:assert/strict");
      const fs = require("node:fs");
      (async () => {
        for (const path of ${JSON.stringify([secret, denied])}) assert.throws(() => fs.readFileSync(path), error => ["EACCES", "EPERM"].includes(error.code));
        assert.notEqual(process.env.CONTEXT7_API_KEY, "fixture-upstream-secret");
        await new Promise((resolve, reject) => {
          const socket = require("node:net").createConnection({ host: "127.0.0.1", port: 23 });
          socket.once("error", error => ["EACCES", "EPERM"].includes(error.code) ? resolve() : reject(error));
          socket.once("connect", () => { socket.destroy(); reject(new Error("ungranted port connected")); });
        });
        const response = await fetch(process.env.CONTEXT7_BASE_URL + "/probe", { headers: { Authorization: "Bearer " + process.env.CONTEXT7_API_KEY }, signal: AbortSignal.timeout(3000) });
        assert.equal(response.status, 200);
        assert.equal(await response.text(), "ok");
      })().catch(error => { console.error(error); process.exitCode = 1; });
    `;
    const command = [process.env.NONO_PROXY_TEST_BINARY, "run", "--profile", f.profile, "--allow-cwd", "--no-audit", "--no-rollback", "--", process.execPath, "-e", probe];
    const runner = `
      import { credentialProxySession } from ${JSON.stringify(new URL("../scripts/credentials/proxy.mts", import.meta.url).href)}; import * as Effect from ${JSON.stringify(import.meta.resolve("effect/Effect"))};
      const result = await Effect.runPromise(credentialProxySession(${JSON.stringify(process.env.NONO_PROXY_TEST_BINARY)}, ${JSON.stringify(f.profile)}, ${JSON.stringify(command)}, process.env, { sandboxed: true }));
      if (result.error) throw result.error;
      process.exit(result.status ?? 1);
    `;
    const child = spawn(process.execPath, ["--input-type=module", "-e", runner], {
      cwd: work, env: { HOME: home, PATH: process.env.PATH, TMPDIR: temporary, NO_COLOR: "1" }, stdio: ["ignore", "pipe", "pipe"],
    });
    const exited = once(child, "exit");
    let output = "";
    child.stdout.on("data", chunk => output += chunk);
    child.stderr.on("data", chunk => output += chunk);
    const [status, signal] = await exited;
    assert.equal(signal, null, output);
    assert.equal(status, 0, output);
    assert.doesNotMatch(output, /fixture-upstream-secret/);
  } finally {
    upstream.closeAllConnections();
    await new Promise(resolve => upstream.close(resolve));
    rmSync(f.root, { recursive: true, force: true });
  }
});
