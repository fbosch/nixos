import { spawn } from "node:child_process";
import { once } from "node:events";
import { closeSync, existsSync, openSync, readFileSync, realpathSync, rmSync, statSync } from "node:fs";
import { isAbsolute, join, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { credentialStoreDirectory } from "./credential-store.mjs";
import { privateIpcBase, privateIpcDirectory } from "./private-ipc.mjs";

export const MODEL_EXECUTOR_SOCKET = "PI_MODEL_EXECUTOR_SOCKET";

/**
 * The executor sees the invoking host environment, not project direnv values, plus the session's
 * agent directory. It writes credential files with the same lock files as `pi --no-sandbox`, not
 * the sandbox's runtime lock directory, so host-side refreshes coordinate across both modes.
 */
export function modelExecutorEnvironment(inherited, agentDir) {
  const executor = { ...inherited, PI_CODING_AGENT_DIR: agentDir };
  for (const name of ["NODE_OPTIONS", "NODE_PATH", "PI_LOCKFILE_DIR", MODEL_EXECUTOR_SOCKET]) delete executor[name];
  return executor;
}

/**
 * Run `run` with a host model executor bound to a private socket for the session's lifetime.
 * `modelsPath` must be an immutable Nix store copy: it decides where credentials may be sent.
 */
export async function withModelExecutor(environment, executorEnvironment, home, packageDir, run, modelsPath) {
  if (!packageDir || !isAbsolute(packageDir) || !existsSync(join(packageDir, "dist", "core", "model-executor.js"))) {
    throw new Error(`Pi model executor package missing: ${packageDir}`);
  }
  if (modelsPath !== undefined && (!modelsPath.startsWith("/nix/store/") || !existsSync(modelsPath))) {
    throw new Error(`Pi model executor models.json must be an existing Nix store path: ${modelsPath}`);
  }
  // The executor's own model catalog cache, kept across sessions where no sandbox grant reaches it.
  const catalogPath = join(privateIpcBase(home), "model-executor-catalog.json");
  // The launcher may block in spawnSync for the whole session, so executor diagnostics go to a
  // file instead of a pipe that nobody drains. Sandboxed sessions can read TMPDIR, not ~/.pi-ipc.
  const logDirectory = privateIpcDirectory(home, "model-log-");
  const logPath = join(logDirectory, "stderr");
  const log = openSync(logPath, "w", 0o600);
  let helper;
  try {
    helper = spawn(process.execPath, [fileURLToPath(new URL("./model-executor.mjs", import.meta.url)), JSON.stringify({ packageDir, home, modelsPath, catalogPath, credentialStore: credentialStoreDirectory(home) })], {
      env: executorEnvironment, stdio: ["pipe", "pipe", log],
    });
  } finally {
    closeSync(log);
  }
  helper.stdin.on("error", () => {});
  const exited = once(helper, "exit");
  const diagnostics = () => {
    try { return readFileSync(logPath, "utf8").slice(-2048).trim(); } catch { return ""; }
  };
  let timer;
  try {
    const endpoint = await new Promise((resolve, reject) => {
      let input = "";
      timer = setTimeout(() => reject(new Error("Pi model executor startup timed out")), 10000);
      helper.once("error", reject);
      helper.once("exit", () => reject(new Error(`Pi model executor exited before readiness: ${diagnostics()}`)));
      helper.stdout.on("data", chunk => {
        input += chunk.toString();
        if (input.length > 4096) return reject(new Error("Invalid Pi model executor readiness frame"));
        if (!input.includes("\n")) return;
        try {
          const ready = JSON.parse(input);
          const base = join(realpathSync(home), ".pi-ipc") + sep;
          if (typeof ready.endpoint !== "string" || !ready.endpoint.startsWith(base) || !statSync(ready.endpoint).isSocket()) {
            throw new Error("Invalid Pi model executor endpoint");
          }
          resolve(ready.endpoint);
        } catch (error) { reject(error); }
      });
    });
    clearTimeout(timer);
    return await run({ ...environment, [MODEL_EXECUTOR_SOCKET]: endpoint });
  } finally {
    clearTimeout(timer);
    helper.stdin.end();
    const timeout = setTimeout(() => helper.kill("SIGTERM"), 2000);
    const hardTimeout = setTimeout(() => helper.kill("SIGKILL"), 4000);
    await exited;
    clearTimeout(timeout);
    clearTimeout(hardTimeout);
    rmSync(logDirectory, { recursive: true, force: true });
  }
}
