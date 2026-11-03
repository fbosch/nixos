import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { spawn } from "node:child_process";
import { closeSync, existsSync, openSync, readFileSync, rmSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { credentialStoreDirectory } from "../credentials/store.mts";
import { awaitHelperEndpoint, privateIpcBase, privateIpcDirectory, scopedHelper } from "../ipc/private.mts";
import { type HostProcessError, LaunchPrerequisiteError, type SandboxError, attempt } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";

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
/**
 * Start the host model executor for one session and expose its private socket. The executor
 * stops when the enclosing scope closes, and its log directory is removed after it exits.
 */
export function modelExecutor(environment: Environment, executorEnvironment: Environment, home: string, packageDir: string | undefined, modelsPath: string | undefined): Effect.Effect<Environment, HostProcessError | LaunchPrerequisiteError | SandboxError, Scope.Scope> {
  return Effect.gen(function* () {
    if (!packageDir || !isAbsolute(packageDir) || !existsSync(join(packageDir, "dist", "core", "model-executor.js"))) {
      return yield* new LaunchPrerequisiteError({ message: `Pi model executor package missing: ${packageDir}; ${OPT_OUT}` });
    }
    if (modelsPath !== undefined && (!modelsPath.startsWith("/nix/store/") || !existsSync(modelsPath))) {
      return yield* new LaunchPrerequisiteError({ message: `Pi model executor models.json must be an existing Nix store path: ${modelsPath}` });
    }
    // The executor's own model catalog cache, kept across sessions where no sandbox grant reaches it.
    const catalogPath = join(yield* attempt(() => privateIpcBase(home)), "model-executor-catalog.json");
    // The launcher may block in spawnSync for the whole session, so executor diagnostics go to a
    // file instead of a pipe that nobody drains. Sandboxed sessions can read TMPDIR, not ~/.pi-ipc.
    const logDirectory = yield* attempt(() => privateIpcDirectory(home, "model-log-"));
    const logPath = join(logDirectory, "stderr");
    const helper = yield* scopedHelper(() => {
      const log = openSync(logPath, "w", 0o600);
      try {
        const child = spawn(process.execPath, [fileURLToPath(new URL("./server.mts", import.meta.url)), JSON.stringify({ packageDir, home, modelsPath, catalogPath, credentialStore: credentialStoreDirectory(home) })], {
          env: executorEnvironment, stdio: ["pipe", "pipe", log],
        });
        child.stdin!.on("error", () => {});
        return child;
      } finally {
        closeSync(log);
      }
    }, { termMs: 2000, killMs: 4000, afterExit: () => rmSync(logDirectory, { recursive: true, force: true }) });
    const diagnostics = () => {
      try { return readFileSync(logPath, "utf8").slice(-2048).trim(); } catch { return ""; }
    };
    const endpoint = yield* awaitHelperEndpoint(helper, home, { name: "Pi model executor", timeoutMs: 10000, diagnostics, hint: OPT_OUT });
    return { ...environment, [MODEL_EXECUTOR_SOCKET]: endpoint };
  });
}
