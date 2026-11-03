import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { once } from "node:events";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { createConnection, createServer } from "node:net";
import { dirname, join } from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";
import { prepareAgentRuntime } from "../scripts/protection/agent.mts";
import { launchArguments } from "../scripts/launch/plan.mts";
import { credentialDenyRule } from "../scripts/protection/shell.mts";
import { MODEL_EXECUTOR_SOCKET, modelExecutorEnvironment, modelExecutor } from "../scripts/model-executor/launch.mts";
import { withScoped } from "./fixtures/scoped.mjs";

const envBinary = process.env.ENV_TEST_BINARY ?? "/usr/bin/env";
const created = [];
afterEach(() => { for (const path of created.splice(0)) rmSync(path, { recursive: true, force: true }); });

function fixture() {
  // Short roots keep Unix socket paths below the macOS sockaddr_un limit.
  const root = realpathSync(mkdtempSync("/tmp/pi-mx-"));
  created.push(root);
  const home = join(root, "home");
  const agent = join(home, ".pi", "agent");
  const cwd = join(root, "work");
  for (const path of [agent, cwd]) mkdirSync(path, { recursive: true });
  const profile = join(root, "pi.json");
  writeFileSync(profile, "{}");
  return { root, home, agent, cwd, profile };
}

function values(args, flag) {
  return args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
}

// A stand-in for the Nix-built Pi package: records how the executor was started.
function fakePackage(root, { failure } = {}) {
  const packageDir = join(root, "package");
  const core = join(packageDir, "dist", "core");
  mkdirSync(core, { recursive: true });
  writeFileSync(join(core, "model-runtime.js"), `
    export class ModelRuntime {
      static async create(options) {
        ${failure ? `throw new Error(${JSON.stringify(failure)});` : ""}
        return { options };
      }
    }
  `);
  writeFileSync(join(core, "model-executor.js"), `
    export function serveModelExecutor(runtime, server) {
      server.on("connection", socket => socket.end(JSON.stringify({
        options: runtime.options,
        env: {
          agent: process.env.PI_CODING_AGENT_DIR ?? null,
          locks: process.env.PI_LOCKFILE_DIR ?? null,
          nodeOptions: process.env.NODE_OPTIONS ?? null,
          executorSocket: process.env.${MODEL_EXECUTOR_SOCKET} ?? null,
          project: process.env.PROJECT_ONLY ?? null,
          host: process.env.HOST_ONLY ?? null,
        },
      })));
    }
  `);
  return packageDir;
}

function request(socket) {
  return new Promise((resolve, reject) => {
    const connection = createConnection(socket);
    const chunks = [];
    connection.once("error", reject);
    connection.on("data", chunk => chunks.push(chunk));
    connection.once("end", () => resolve(JSON.parse(Buffer.concat(chunks).toString("utf8"))));
  });
}

test("the executor environment comes from the invoking host and uses raw-mode credential locks", () => {
  const inherited = { HOST_ONLY: "1", NODE_OPTIONS: "--require /tmp/x.js", NODE_PATH: "/tmp", PI_LOCKFILE_DIR: "/sandbox-locks", [MODEL_EXECUTOR_SOCKET]: "/forged" };
  assert.deepEqual(modelExecutorEnvironment(inherited, "/agent"), { HOST_ONLY: "1", PI_CODING_AGENT_DIR: "/agent" });
});

test("the executor runs from the Pi package on a private socket for the session", async () => {
  const { root, home } = fixture();
  const packageDir = fakePackage(root);
  const executorEnvironment = modelExecutorEnvironment({ HOST_ONLY: "1", NODE_OPTIONS: "--trace-warnings", PI_LOCKFILE_DIR: "/locks", PATH: process.env.PATH }, "/agent");
  let endpoint;
  const result = await withScoped(modelExecutor({ PROJECT_ONLY: "1", [MODEL_EXECUTOR_SOCKET]: "/forged" }, executorEnvironment, home, packageDir), async environment => {
    endpoint = environment[MODEL_EXECUTOR_SOCKET];
    assert.ok(endpoint.startsWith(join(home, ".pi-ipc") + "/"));
    assert.equal(environment.PROJECT_ONLY, "1");
    return request(endpoint);
  });
  assert.deepEqual(result, {
    options: { executorSocket: null, modelsPath: null, modelsStorePath: join(home, ".pi-ipc", "model-executor-catalog.json") },
    env: { agent: "/agent", locks: null, nodeOptions: null, executorSocket: null, project: null, host: "1" },
  });
  assert.equal(existsSync(dirname(endpoint)), false, "session end removes the executor socket directory");
  assert.deepEqual(readdirSync(join(home, ".pi-ipc")), [], "session end removes executor diagnostics");
});

test("executor startup failures stop the launch with the executor's diagnostics", async () => {
  const { root, home } = fixture();
  const packageDir = fakePackage(root, { failure: "fixture executor startup failure" });
  let ran = false;
  await assert.rejects(
    withScoped(modelExecutor({}, { PATH: process.env.PATH }, home, packageDir), async () => { ran = true; }),
    /exited before readiness: .*fixture executor startup failure/s,
  );
  assert.equal(ran, false);
  await assert.rejects(withScoped(modelExecutor({}, {}, home, join(root, "missing")), async () => {}), /package missing/);
});

test("the executor's models.json must be an immutable store copy", async () => {
  const { root, home, agent } = fixture();
  const packageDir = fakePackage(root);
  writeFileSync(join(agent, "models.json"), "{}");
  let ran = false;
  // A sandboxed configuration session can edit the agent directory's models.json.
  await assert.rejects(
    withScoped(modelExecutor({}, { PATH: process.env.PATH }, home, packageDir, join(agent, "models.json")), async () => { ran = true; }),
    /must be an existing Nix store path/,
  );
  assert.equal(ran, false);
});

test("the sandbox receives only a private executor socket grant", async () => {
  const { root, home, agent, cwd, profile } = fixture();
  const directory = join(home, ".pi-ipc", "model-x");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const socket = join(directory, "s");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try {
    const args = launchArguments(cwd, agent, home, { [MODEL_EXECUTOR_SOCKET]: socket }, profile, process.execPath, envBinary, "darwin");
    assert.deepEqual(values(args, "--allow-unix-socket"), [socket]);
    assert.deepEqual(values(launchArguments(cwd, agent, home, {}, profile, process.execPath, envBinary, "darwin"), "--allow-unix-socket"), []);
    const outside = join(root, "outside.sock");
    assert.throws(() => launchArguments(cwd, agent, home, { [MODEL_EXECUTOR_SOCKET]: outside }, profile, process.execPath, envBinary, "darwin"), /private Pi IPC socket/);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test("raw mode does not inherit an executor socket", () => {
  const { home, cwd, agent, profile } = fixture();
  const script = `console.log(JSON.stringify(process.env.${MODEL_EXECUTOR_SOCKET} ?? null))`;
  const child = spawnSync(process.execPath, [
    fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url)),
    "/missing-nono", process.execPath, profile, "/missing-direnv", "/missing-env", "--no-sandbox", "-e", script,
  ], {
    cwd,
    env: { HOME: home, PATH: process.env.PATH, PI_CODING_AGENT_DIR: agent, PI_MODEL_EXECUTOR: "1", [MODEL_EXECUTOR_SOCKET]: "/tmp/other-session.sock" },
    encoding: "utf8", timeout: 10000,
  });
  assert.ifError(child.error);
  assert.equal(child.status, 0, child.stderr);
  assert.equal(JSON.parse(child.stdout), null);
});

test("executor mode grants the sandbox no credential files", async () => {
  const { home, agent, cwd, profile } = fixture();
  prepareAgentRuntime(agent);
  writeFileSync(join(agent, "auth.json"), "{}", { mode: 0o600 });
  const directory = join(home, ".pi-ipc", "model-y");
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  const socket = join(directory, "s");
  const server = createServer(connection => connection.end());
  server.listen(socket);
  await once(server, "listening");
  try {
    const grants = (args) => [...values(args, "--allow"), ...values(args, "--allow-file"), ...values(args, "--read"), ...values(args, "--read-file")];
    const ordinary = launchArguments(cwd, agent, home, {}, profile, process.execPath, envBinary, "darwin");
    assert.ok(grants(ordinary).includes(join(agent, "auth.json")), "without the executor Pi refreshes auth.json in place");
    assert.ok(grants(ordinary).includes(join(agent, "auth-profiles")));
    const executor = launchArguments(cwd, agent, home, { [MODEL_EXECUTOR_SOCKET]: socket }, profile, process.execPath, envBinary, "darwin");
    const credentials = [join(agent, "auth.json"), join(agent, "auth-profiles")];
    const writable = [...values(executor, "--allow"), ...values(executor, "--allow-file")];
    for (const path of writable) {
      assert.ok(!credentials.some((credential) => path === credential || path.startsWith(`${credential}/`)), path);
    }
    // The profile directory stays listable; the session profile denies the files inside it.
    assert.deepEqual(
      [...values(executor, "--read"), ...values(executor, "--read-file")].filter((path) => credentials.some((credential) => path.startsWith(credential))),
      [join(agent, "auth-profiles")],
    );
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test("the macOS credential denial covers auth.json, its locks and profile files but keeps profiles listable", () => {
  const rule = credentialDenyRule(["/Users/a.b/.pi/agent/auth.json", "/Users/a.b/.pi/agent/auth-profiles"]);
  assert.equal(rule, '(deny file-read* file-write* (regex #"^/Users/a\\.b/\\.pi/agent/auth\\.json") (regex #"^/Users/a\\.b/\\.pi/agent/auth-profiles/"))');
  assert.equal(credentialDenyRule([]), undefined);
});

function launchSandbox({ root, home, agent, cwd, profile }, environment) {
  const nono = join(root, "nono");
  writeFileSync(nono, `#!${process.execPath}\nconsole.log(JSON.stringify({ args: process.argv.slice(2), socket: process.env.${MODEL_EXECUTOR_SOCKET} ?? null }));\n`, { mode: 0o700 });
  // A project .envrc asking to disable the executor; only the invoking host may opt out.
  const direnv = join(root, "direnv");
  writeFileSync(direnv, `#!${process.execPath}\nconsole.log(JSON.stringify({ PI_MODEL_EXECUTOR: "0" }));\n`, { mode: 0o700 });
  writeFileSync(join(cwd, ".envrc"), "fixture");
  const runtime = join(root, "runtime");
  mkdirSync(runtime, { recursive: true });
  const child = spawnSync(process.execPath, [fileURLToPath(new URL("../scripts/launcher.mts", import.meta.url)), nono, process.execPath, profile, direnv, envBinary, "--version"], {
    cwd,
    env: { HOME: home, PATH: process.env.PATH, PI_CODING_AGENT_DIR: agent, TMPDIR: runtime, XDG_RUNTIME_DIR: runtime, ...environment },
    encoding: "utf8", timeout: 20000,
  });
  assert.ifError(child.error);
  return child;
}

test("sandboxed launches use the host model executor unless the invoking host opts out", () => {
  const f = fixture();
  const packageDir = fakePackage(f.root);
  const executor = launchSandbox(f, { PI_MODEL_EXECUTOR_PACKAGE: packageDir });
  assert.equal(executor.status, 0, executor.stderr);
  const launched = JSON.parse(executor.stdout);
  assert.ok(launched.socket?.startsWith(join(f.home, ".pi-ipc") + "/"), "the project .envrc cannot disable the executor");
  assert.ok(values(launched.args, "--allow-unix-socket").includes(launched.socket));

  const optedOut = launchSandbox(f, { PI_MODEL_EXECUTOR_PACKAGE: packageDir, PI_MODEL_EXECUTOR: "0" });
  assert.equal(optedOut.status, 0, optedOut.stderr);
  const raw = JSON.parse(optedOut.stdout);
  assert.equal(raw.socket, null);
  assert.ok(!values(raw.args, "--allow-unix-socket").some(path => path.startsWith(join(f.home, ".pi-ipc", "model-"))));
});

test("a sandboxed launch without the executor package stops before nono runs", () => {
  const f = fixture();
  const child = launchSandbox(f, {});
  assert.equal(child.status, 1);
  assert.equal(child.stdout, "");
  assert.match(child.stderr, /executor package missing.*PI_MODEL_EXECUTOR=0/);
});
