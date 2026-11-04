import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const transport = fileURLToPath(new URL("../scripts/launch/ssh-transport.mts", import.meta.url));
const ssh = process.env.SSH_TEST_BINARY;

function run(args, environment = {}, input = "") {
  return runProgram(process.execPath, [transport, ...args], environment, input);
}

function runProgram(binary, args, environment, input = "") {
  const child = spawn(binary, args, {
    env: { PATH: process.env.PATH, ...environment }, stdio: ["pipe", "pipe", "pipe"], timeout: 5000,
  });
  let stdout = "", stderr = "";
  child.stdout.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
  child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
  child.stdin.on("error", () => {});
  child.stdin.end(input);
  const done = once(child, "close").then(([status]) => ({ status, stdout, stderr }));
  return { child, done };
}

async function withProxy(handler, use) {
  const sockets = new Set();
  const server = createServer(socket => {
    sockets.add(socket);
    socket.once("close", () => sockets.delete(socket));
    handler(socket);
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  try {
    await use(`http://nono:fixture-token@127.0.0.1:${server.address().port}`);
  } finally {
    for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  }
}

test("Azure SSH uses authenticated CONNECT and preserves banner bytes and half-close", { timeout: 10000 }, async () => {
  await withProxy(socket => {
    let request = "";
    socket.on("data", function header(chunk) {
      request += chunk;
      if (!request.includes("\r\n\r\n")) return;
      socket.removeListener("data", header);
      assert.match(request, /^CONNECT vs-ssh\.visualstudio\.com:22 HTTP\/1\.1\r\n/);
      assert.ok(request.includes(`Proxy-Authorization: Basic ${Buffer.from("nono:fixture-token").toString("base64")}\r\n`));
      // Fragment the header, then coalesce its end with the first SSH bytes.
      socket.write("HTTP/1.1 200 Connection Established\r\n");
      socket.write("\r\nSSH-2.0-fixture\r\n");
      socket.on("data", data => socket.write(data));
    });
  }, async HTTP_PROXY => {
    const result = await run(["connect", "vs-ssh.visualstudio.com", "22"], { HTTP_PROXY }, "SSH-2.0-client\r\n").done;
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, "SSH-2.0-fixture\r\nSSH-2.0-client\r\n");
    assert.equal(result.stderr, "");
  });
});

test("Azure SSH rejects proxy refusal without relaying response bodies or credentials", { timeout: 10000 }, async () => {
  await withProxy(socket => socket.once("data", () => socket.end("HTTP/1.1 407 Proxy Authentication Required\r\n\r\nsecret-body")), async HTTP_PROXY => {
    const result = await run(["connect", "ssh.dev.azure.com", "22"], { HTTP_PROXY }).done;
    assert.equal(result.status, 1);
    assert.equal(result.stdout, "");
    assert.match(result.stderr, /407/);
    assert.doesNotMatch(result.stderr, /fixture-token|secret-body/);
  });
});

test("Azure SSH fails closed on oversized and truncated CONNECT responses", { timeout: 10000 }, async () => {
  for (const response of ["HTTP/1.1 200 OK\r\nX: " + "x".repeat(17000), "HTTP/1.1 200 OK\r\n"]) {
    await withProxy(socket => socket.once("data", () => socket.end(response)), async HTTP_PROXY => {
      const result = await run(["connect", "ssh.dev.azure.com", "22"], { HTTP_PROXY }).done;
      assert.equal(result.status, 1);
      assert.equal(result.stdout, "");
      assert.match(result.stderr, /CONNECT/);
    });
  }
});

test("Azure SSH rejects unsupported destinations, ports, and nonlocal or missing proxies", async () => {
  for (const [host, port, HTTP_PROXY] of [
    ["evil.example", "22", "http://127.0.0.1:1"],
    ["ssh.dev.azure.com.evil.example", "22", "http://127.0.0.1:1"],
    ["ssh.dev.azure.com", "443", "http://127.0.0.1:1"],
    ["ssh.dev.azure.com", "22", undefined],
    ["ssh.dev.azure.com", "22", "http://nono:fixture-token@evil.example:8080"],
    ["ssh.dev.azure.com", "22", "http://127.0.0.1:1/path"],
    ["ssh.dev.azure.com", "22", "not-a-url"],
  ]) {
    const result = await run(["connect", host, port], HTTP_PROXY ? { HTTP_PROXY } : {}).done;
    assert.equal(result.status, 1);
    assert.match(result.stderr, /pi SSH:/);
    assert.doesNotMatch(result.stderr, /fixture-token/);
    assert.equal(result.stdout, "");
  }
});

test("SSH client wrapper adds proxy configuration only inside nono and preserves arguments", async () => {
  const directory = mkdtempSync(join(tmpdir(), "pi-ssh-client-"));
  try {
    const fakeSsh = join(directory, "ssh");
    writeFileSync(fakeSsh, `#!${process.execPath}\nconsole.log(JSON.stringify(process.argv.slice(2)));\n`, { mode: 0o700 });
    for (const confined of [false, true]) {
      const result = await run(["client", fakeSsh, "/pinned/ssh.conf", "-p", "22", "git@ssh.dev.azure.com", "git-upload-pack 'project/repo'"], confined ? { NONO_CAP_FILE: "/session/caps.json" } : {}).done;
      assert.equal(result.status, 0, result.stderr);
      assert.deepEqual(JSON.parse(result.stdout), [
        ...(confined ? ["-F", "/pinned/ssh.conf"] : []),
        "-p", "22", "git@ssh.dev.azure.com", "git-upload-pack 'project/repo'",
      ]);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});

async function withConfig(use) {
  if (process.env.PI_TEST_SSH_CONFIG) return use(process.env.PI_TEST_SSH_CONFIG);
  const directory = mkdtempSync(join(tmpdir(), "pi-ssh-config-"));
  try {
    const source = readFileSync(new URL("../scripts/launch/ssh_config", import.meta.url), "utf8");
    const config = join(directory, "ssh_config");
    writeFileSync(config, source.replaceAll("@node@", process.execPath).replaceAll("@transport@", transport));
    return await use(config);
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("SSH configuration routes Azure only and preserves explicit identity and host verification", { skip: !ssh }, async () => {
  await withConfig(async config => {
    for (const host of ["ssh.dev.azure.com", "vs-ssh.visualstudio.com", "unrelated.example"]) {
      const result = await run(["client", ssh, config, "-G", "-o", "StrictHostKeyChecking=yes", "-o", "IdentityFile=/fixture/identity.pub", host], { NONO_CAP_FILE: "/session/caps.json" }).done;
      assert.equal(result.status, 0, result.stderr);
      if (host === "unrelated.example") assert.doesNotMatch(result.stdout, /^proxycommand .*ssh-transport/m);
      else assert.match(result.stdout, /^proxycommand .*ssh-transport\.mts connect %h %p$/m);
      assert.match(result.stdout, /^stricthostkeychecking true$/m);
      assert.match(result.stdout, /^identityfile \/fixture\/identity.pub$/m);
    }
  });
});

test("Git reaches Azure's SSH handshake through CONNECT without direct SSH egress", {
  skip: !ssh || !process.env.GIT_TEST_BINARY, timeout: 10000,
}, async () => {
  await withConfig(async config => {
    let request = "", clientBanner = "";
    await withProxy(socket => {
      socket.on("data", function header(chunk) {
        request += chunk;
        if (!request.includes("\r\n\r\n")) return;
        socket.removeListener("data", header);
        socket.write("HTTP/1.1 200 Connection Established\r\n\r\nSSH-2.0-fixture\r\n");
        socket.once("data", data => {
          clientBanner = data.toString();
          socket.end();
        });
      });
    }, async HTTP_PROXY => {
      const command = process.env.PI_TEST_SSH_BINARY ? [process.env.PI_TEST_SSH_BINARY]
        : [process.execPath, transport, "client", ssh, config];
      const GIT_SSH_COMMAND = command.map(value => `'${value.replaceAll("'", "'\\''")}'`).join(" ");
      const result = await runProgram(process.env.GIT_TEST_BINARY, ["ls-remote", "git@vs-ssh.visualstudio.com:fixture/repo"], {
        HTTP_PROXY, NONO_CAP_FILE: "/session/caps.json", GIT_SSH_COMMAND, GIT_SSH_VARIANT: "ssh",
        GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_TERMINAL_PROMPT: "0",
      }).done;
      // The synthetic server ends after banner exchange, before keys or authentication.
      assert.equal(result.status, 128, result.stderr);
    });
    assert.match(request, /^CONNECT vs-ssh\.visualstudio\.com:22 HTTP\/1\.1\r\n/);
    assert.match(clientBanner, /^SSH-2\.0-/);
  });
});
