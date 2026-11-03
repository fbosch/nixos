import { spawn, type ChildProcess } from "node:child_process";
import { once } from "node:events";
import { closeSync, existsSync, openSync, readFileSync, rmSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { credentialStoreDirectory } from "../credentials/store.mts";
import { helperEndpoint, privateIpcBase, privateIpcDirectory } from "../ipc/private.mts";
import type { Environment, SessionStep } from "../shared/types.mts";

export const MODEL_EXECUTOR_SOCKET = "PI_MODEL_EXECUTOR_SOCKET";
const OPT_OUT = "set PI_MODEL_EXECUTOR=0 to launch without it; the sandbox can then read the credential files";

/** Sandboxed sessions use the executor unless the invoking host environment sets PI_MODEL_EXECUTOR=0. */
export function modelExecutorEnabled(inherited: Environment): boolean {
  return inherited.PI_MODEL_EXECUTOR !== "0";
}

/**
 * The executor sees the invoking host environment, not project direnv values, plus the session's
 * agent directory. It writes credential files with the same lock files as `pi --no-sandbox`, not
 * the sandbox's runtime lock directory, so host-side refreshes coordinate across both modes.
 */
export function modelExecutorEnvironment(inherited: Environment, agentDir: string): Environment {
  const executor: Environment = { ...inherited, PI_CODING_AGENT_DIR: agentDir };
  for (const name of ["NODE_OPTIONS", "NODE_PATH", "PI_LOCKFILE_DIR", MODEL_EXECUTOR_SOCKET]) delete executor[name];
  return executor;
}

/**
 * Run `run` with a host model executor bound to a private socket for the session's lifetime.
 * `modelsPath` must be an immutable Nix store copy: it decides where credentials may be sent.
 */
export async function withModelExecutor<T>(environment: Environment, executorEnvironment: Environment, home: string, packageDir: string | undefined, run: SessionStep<T>, modelsPath: string | undefined): Promise<T> {
  if (!packageDir || !isAbsolute(packageDir) || !existsSync(join(packageDir, "dist", "core", "model-executor.js"))) {
    throw new Error(`Pi model executor package missing: ${packageDir}; ${OPT_OUT}`);
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
  let helper: ChildProcess;
  try {
    helper = spawn(process.execPath, [fileURLToPath(new URL("./server.mts", import.meta.url)), JSON.stringify({ packageDir, home, modelsPath, catalogPath, credentialStore: credentialStoreDirectory(home) })], {
      env: executorEnvironment, stdio: ["pipe", "pipe", log],
    });
  } finally {
    closeSync(log);
  }
  helper.stdin!.on("error", () => {});
  const exited = once(helper, "exit");
  const diagnostics = () => {
    try { return readFileSync(logPath, "utf8").slice(-2048).trim(); } catch { return ""; }
  };
  try {
    const endpoint = await helperEndpoint(helper, home, { name: "Pi model executor", timeoutMs: 10000, diagnostics, hint: OPT_OUT });
    return await run({ ...environment, [MODEL_EXECUTOR_SOCKET]: endpoint });
  } finally {
    helper.stdin!.end();
    const timeout = setTimeout(() => helper.kill("SIGTERM"), 2000);
    const hardTimeout = setTimeout(() => helper.kill("SIGKILL"), 4000);
    await exited;
    clearTimeout(timeout);
    clearTimeout(hardTimeout);
    rmSync(logDirectory, { recursive: true, force: true });
  }
}
