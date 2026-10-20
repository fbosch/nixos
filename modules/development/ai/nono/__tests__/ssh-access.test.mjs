import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, linkSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { launchArguments } from "../scripts/launcher.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";

const profile = fileURLToPath(new URL("../scripts/profile.json", import.meta.url));
const created = [];
// Fake credentials must stay outside shared temporary-directory read grants.
function fixture(base = process.cwd()) {
  const root = realpathSync(mkdtempSync(join(base, ".pi-ssh-")));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const cwd = join(root, "work");
  const ssh = join(home, ".ssh");
  const temporary = join(root, "tmp");
  const runtime = join(root, "runtime");
  for (const path of [agent, cwd, temporary, runtime]) mkdirSync(path, { recursive: true });
  const args = (environment = {}) => launchArguments(cwd, agent, home, { TMPDIR: temporary, XDG_RUNTIME_DIR: runtime, ...environment }, profile, process.execPath, envBinary);
  return { root, home, agent, cwd, ssh, args };
}
afterEach(() => {
  for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true });
});
function paths(args, flag) {
  return args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
}

const publicFiles = ["config", "known_hosts", "known_hosts2", "id_rsa.pub", "id_ed25519.pub", "id_ecdsa.pub"];

test("SSH client state receives exact read-only grants and credential-deny exemptions, never private keys", () => {
  const f = fixture();
  mkdirSync(f.ssh);
  for (const name of [...publicFiles, "id_rsa", "id_ed25519", "unrelated"]) writeFileSync(join(f.ssh, name), "fixture");
  const args = f.args();
  const expected = publicFiles.map(name => join(f.ssh, name));
  assert.deepEqual(paths(args, "--read-file"), expected);
  assert.deepEqual(paths(args, "--bypass-protection"), expected);
  for (const flag of ["--allow", "--read", "--allow-file", "--write-file"]) {
    assert.ok(!paths(args, flag).some(path => path === f.ssh || path.startsWith(`${f.ssh}/`)), flag);
  }
});

test("SSH read exceptions cannot inherit writes from cwd, runtime, or aliased launcher grants", () => {
  const f = fixture();
  mkdirSync(f.ssh);
  writeFileSync(join(f.ssh, "known_hosts"), "fixture");
  assert.throws(() => f.args({ PI_HASHLINE_DIR: f.ssh }), /SSH client file overlaps a writable launcher grant/);
  assert.throws(() => f.args({ XDG_RUNTIME_DIR: f.ssh }), /SSH client file overlaps a writable launcher grant/);
  assert.throws(() => launchArguments(f.home, f.agent, f.home, {}, profile, process.execPath, envBinary), /SSH client file overlaps a writable launcher grant/);
  const alias = join(f.root, "ssh-alias");
  symlinkSync(f.ssh, alias);
  assert.throws(() => f.args({ PI_HASHLINE_DIR: alias }), /SSH client file overlaps a writable launcher grant/);
  const sibling = `${f.ssh}-sibling`;
  mkdirSync(sibling);
  assert.doesNotThrow(() => f.args({ PI_HASHLINE_DIR: sibling }));
});

test("missing optional SSH client files neither create trust state nor grant the SSH directory", () => {
  const f = fixture();
  assert.deepEqual(paths(f.args(), "--read-file"), []);
  assert.deepEqual(paths(f.args(), "--bypass-protection"), []);
  assert.equal(existsSync(f.ssh), false);
  mkdirSync(f.ssh);
  writeFileSync(join(f.ssh, "known_hosts"), "fixture");
  assert.deepEqual(paths(f.args(), "--read-file"), [join(f.ssh, "known_hosts")]);
});

test("public SSH filenames cannot expose private keys through symlinks or hard links", () => {
  const f = fixture();
  mkdirSync(f.ssh);
  const privateKey = join(f.ssh, "id_rsa");
  const known = join(f.ssh, "known_hosts");
  writeFileSync(privateKey, "private fixture");
  symlinkSync(privateKey, known);
  assert.throws(() => f.args(), /SSH client.*symlink/);
  rmSync(known);
  linkSync(privateKey, known);
  assert.throws(() => f.args(), /SSH client.*hard.link/);
});

test("SSH directory aliases cannot manufacture public-file exceptions", () => {
  const f = fixture();
  const external = join(f.root, "external");
  mkdirSync(external);
  symlinkSync(external, f.ssh);
  assert.throws(() => f.args(), /SSH client directory.*symlink/);
});

test("immutable Nix-managed SSH config symlinks are supported", {
  skip: !realpathSync(process.execPath).startsWith("/nix/store/"),
}, () => {
  const f = fixture();
  mkdirSync(f.ssh);
  symlinkSync(process.execPath, join(f.ssh, "config"));
  assert.deepEqual(paths(f.args(), "--read-file"), [join(f.ssh, "config")]);
});

test("SSH_AUTH_SOCK grants only connect access to the selected existing agent socket", async () => {
  const f = fixture();
  const socket = join(f.root, "agent.sock");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try {
    const args = f.args({ SSH_AUTH_SOCK: socket });
    assert.deepEqual(paths(args, "--allow-unix-socket"), [socket]);
    assert.deepEqual(paths(args, "--bypass-protection"), [socket]);
    assert.ok(!paths(args, "--allow").includes(f.root));
    assert.ok(!paths(args, "--read").includes(f.root));
    assert.deepEqual(paths(args, "--allow-unix-socket-bind"), []);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test("invalid SSH agent paths fail loudly instead of granting a file or a directory", () => {
  const f = fixture();
  const file = join(f.root, "not-a-socket");
  writeFileSync(file, "fixture");
  assert.throws(() => f.args({ SSH_AUTH_SOCK: "relative.sock" }), /SSH_AUTH_SOCK.*absolute/);
  assert.throws(() => f.args({ SSH_AUTH_SOCK: file }), /SSH_AUTH_SOCK.*socket/);
  assert.throws(() => f.args({ SSH_AUTH_SOCK: join(f.root, "missing.sock") }), /SSH_AUTH_SOCK.*ENOENT/);
});

function sshFixture() {
  // Shared temporary-directory grants would mask credential and read-only enforcement failures.
  const f = fixture(process.cwd());
  mkdirSync(f.ssh);
  const blob = Buffer.concat([Buffer.from([0, 0, 0, 11]), Buffer.from("ssh-ed25519"), Buffer.from([0, 0, 0, 32]), Buffer.alloc(32)]);
  const publicKey = `ssh-ed25519 ${blob.toString("base64")}`;
  writeFileSync(join(f.ssh, "known_hosts"), `sandbox.example ${publicKey}\n`);
  writeFileSync(join(f.ssh, "id_ed25519.pub"), `${publicKey}\n`);
  writeFileSync(join(f.ssh, "config"), "Host sandbox.example\n  IdentitiesOnly yes\n  IdentityFile ~/.ssh/id_ed25519\n");
  for (const name of ["id_ed25519", "unrelated"]) writeFileSync(join(f.ssh, name), "private fixture");
  const environment = {
    ...process.env,
    HOME: f.home,
    XDG_CONFIG_HOME: join(f.home, ".config"),
    XDG_CACHE_HOME: join(f.home, ".cache"),
    XDG_DATA_HOME: join(f.home, ".local", "share"),
    XDG_STATE_HOME: join(f.root, "state"),
    TMPDIR: join(f.root, "tmp"),
  };
  delete environment.SSH_AUTH_SOCK;
  for (const name of ["XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "TMPDIR"]) {
    mkdirSync(environment[name], { recursive: true });
  }
  return { ...f, environment };
}

test("Nono resolves SSH client grants and keeps known-host writes and private-key reads denied", {
  skip: !process.env.NONO_TEST_BINARY,
}, () => {
  const f = sshFixture();
  const args = f.args(f.environment);
  args.splice(args.indexOf("--"), 0, "--dry-run");
  const dryRun = spawnSync(process.env.NONO_TEST_BINARY, args, { cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 10000 });
  assert.ifError(dryRun.error);
  assert.equal(dryRun.status, 0, dryRun.stderr);
  assert.ok(`${dryRun.stdout}${dryRun.stderr}`.includes(join(f.ssh, "known_hosts")));

  const policy = JSON.parse(readFileSync(profile, "utf8"));
  policy.filesystem.read_file = paths(args, "--read-file");
  policy.filesystem.bypass_protection = paths(args, "--bypass-protection");
  const candidate = join(f.root, "candidate.json");
  writeFileSync(candidate, JSON.stringify(policy));
  for (const [name, operation, status] of [
    ["known_hosts", "read", "allowed"],
    ["known_hosts", "write", "denied"],
    ["id_ed25519.pub", "read", "allowed"],
    ["id_ed25519.pub", "write", "denied"],
    ["id_ed25519", "read", "denied"],
    ["unrelated", "read", "denied"],
  ]) {
    const check = spawnSync(process.env.NONO_TEST_BINARY, [
      "why", "--profile", candidate, "--path", join(f.ssh, name), "--op", operation, "--json",
    ], { cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 10000 });
    assert.ifError(check.error);
    assert.equal(check.status, 0, check.stderr);
    assert.equal(JSON.parse(check.stdout).status, status, `${name}: ${operation}`);
  }
});

test("Nono resolves an exact agent socket exemption inside the protected SSH directory", {
  skip: !process.env.NONO_TEST_BINARY,
}, async () => {
  const f = sshFixture();
  const socket = join(f.ssh, "agent.sock");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try {
    f.environment.SSH_AUTH_SOCK = socket;
    const args = f.args(f.environment);
    args.splice(args.indexOf("--"), 0, "--dry-run");
    const result = spawnSync(process.env.NONO_TEST_BINARY, args, { cwd: f.cwd, env: f.environment, encoding: "utf8", timeout: 10000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stderr);
    assert.ok(`${result.stdout}${result.stderr}`.includes(socket));
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

function runSandbox(binary, args, options) {
  return new Promise((resolve, reject) => {
    const child = spawn(binary, args, { ...options, detached: true });
    let stdout = "";
    let stderr = "";
    const timeout = setTimeout(() => {
      if (child.pid) {
        try { process.kill(-child.pid, "SIGKILL"); }
        catch (error) { if (error.code !== "ESRCH") reject(error); }
      }
      child.stdout.destroy();
      child.stderr.destroy();
      reject(new Error("SSH sandbox probe timed out"));
    }, 30000);
    child.stdout.setEncoding("utf8").on("data", chunk => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", chunk => { stderr += chunk; });
    child.once("error", error => { clearTimeout(timeout); reject(error); });
    child.once("close", status => { clearTimeout(timeout); resolve({ status, stdout, stderr }); });
  });
}

test("Nono permits OpenSSH host verification and agent queries without private-key access", {
  skip: !process.env.NONO_TEST_BINARY,
}, async () => {
  const f = sshFixture();
  const socket = join(f.ssh, "agent.sock");
  let queries = 0;
  const server = createServer(connection => {
    let request = Buffer.alloc(0);
    connection.on("data", chunk => {
      request = Buffer.concat([request, chunk]);
      if (request.length < 4 || request.length < request.readUInt32BE(0) + 4) return;
      assert.equal(request[4], 11, "SSH_AGENTC_REQUEST_IDENTITIES");
      queries++;
      connection.end(Buffer.from([0, 0, 0, 5, 12, 0, 0, 0, 0]));
    });
  });
  server.listen(socket);
  await once(server, "listening");
  try {
    f.environment.SSH_AUTH_SOCK = socket;
    const probe = fileURLToPath(new URL("./fixtures/ssh-access-probe.mjs", import.meta.url));
    const args = f.args(f.environment);
    args.splice(args.indexOf("--"), 0, "--read-file", probe);
    const result = await runSandbox(process.env.NONO_TEST_BINARY, [
      ...args, probe, f.ssh, process.env.SSH_KEYGEN_TEST_BINARY || "ssh-keygen", process.env.SSH_ADD_TEST_BINARY || "ssh-add",
    ], { cwd: f.cwd, env: f.environment });
    assert.equal(result.status, 0, result.stderr || result.stdout);
    assert.equal(queries, 1);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});
