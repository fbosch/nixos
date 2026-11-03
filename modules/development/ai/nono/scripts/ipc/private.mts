import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { once } from "node:events";
import { lstatSync, mkdirSync, mkdtempSync, realpathSync, statSync } from "node:fs";
import type { ChildProcess } from "node:child_process";
import { join, sep } from "node:path";
import { GrantConflictError, type HostProcessError, type SandboxError, UnsafeFileError, attempt, hostProcessError } from "../shared/errors.mts";
import type { ErrnoError } from "../shared/types.mts";
import { grantedPaths, type GrantPlan } from "../shared/grant-plan.mts";

/** Path prefix of private IPC state. Unlike privateIpcBase, it never creates the directory. */
export function privateIpcPrefix(home: string): string {
  return join(realpathSync(home), ".pi-ipc") + sep;
}

/** The private, user-owned IPC state directory; no sandbox grant may cover it. */
export function privateIpcBase(home: string): string {
  const base = join(realpathSync(home), ".pi-ipc");
  try {
    mkdirSync(base, { mode: 0o700 });
  } catch (error) {
    if ((error as ErrnoError).code !== "EEXIST") throw error;
  }
  const entry = lstatSync(base);
  if (!entry.isDirectory() || entry.uid !== process.getuid!() || (entry.mode & 0o077) !== 0) {
    throw new UnsafeFileError({ message: "Pi IPC state must be a private, user-owned directory without symlinks" });
  }
  return base;
}

export function privateIpcDirectory(home: string, prefix: string): string {
  return mkdtempSync(join(privateIpcBase(home), prefix));
}

/**
 * Resolve the endpoint a host helper announces as one JSON line on stdout. The endpoint must be
 * an existing socket inside private IPC state. Rejects on timeout, early exit, or an invalid frame.
 */
export interface HelperEndpointOptions {
  /** Helper name used in every error message. */
  name: string;
  timeoutMs: number;
  /** Recent helper stderr, reported when the helper exits before readiness. */
  diagnostics: () => string;
  /** Remedy appended to timeout and early-exit errors. */
  hint?: string;
}

function helperEndpoint(helper: ChildProcess, home: string, { name, timeoutMs, diagnostics, hint }: HelperEndpointOptions): Promise<string> {
  const withHint = (message: string, separator: string) => hint ? `${message}${separator}${hint}` : message;
  let timer: NodeJS.Timeout | undefined;
  return new Promise<string>((resolve, reject) => {
    let input = "";
    timer = setTimeout(() => reject(new Error(withHint(`${name} startup timed out`, "; "))), timeoutMs);
    helper.once("error", reject);
    helper.once("exit", () => reject(new Error(withHint(`${name} exited before readiness: ${diagnostics()}`, "\n"))));
    helper.stdout!.on("data", (chunk: Buffer) => {
      input += chunk.toString();
      if (input.length > 4096) return reject(new Error(`Invalid ${name} readiness frame`));
      if (!input.includes("\n")) return;
      try {
        const ready: { endpoint?: unknown } = JSON.parse(input);
        if (typeof ready.endpoint !== "string" || !ready.endpoint.startsWith(privateIpcPrefix(home)) || !statSync(ready.endpoint).isSocket()) {
          throw new Error(`Invalid ${name} endpoint`);
        }
        resolve(ready.endpoint);
      } catch (error) { reject(error); }
    });
  }).finally(() => clearTimeout(timer));
}

/** Grace periods before an unresponsive helper receives SIGTERM and then SIGKILL. */
export interface HelperStop {
  termMs: number;
  killMs: number;
  /** Runs after the helper exits, for example to remove its log directory. */
  afterExit?: () => void;
}

/**
 * A host helper process owned by the current scope. Closing stdin asks it to stop; it receives
 * SIGTERM and SIGKILL only if it outlives the grace periods. Cleanup is registered before the
 * caller waits for readiness, so a helper that never becomes ready is still stopped.
 */
export function scopedHelper(spawnHelper: () => ChildProcess, { termMs, killMs, afterExit }: HelperStop): Effect.Effect<ChildProcess, never, Scope.Scope> {
  return Effect.acquireRelease(
    Effect.sync(() => {
      const helper = spawnHelper();
      return { helper, exited: once(helper, "exit") };
    }),
    ({ helper, exited }) => Effect.promise(async () => {
      helper.stdin!.end();
      const timeout = setTimeout(() => helper.kill("SIGTERM"), termMs);
      const hardTimeout = setTimeout(() => helper.kill("SIGKILL"), killMs);
      await exited;
      clearTimeout(timeout);
      clearTimeout(hardTimeout);
      afterExit?.();
    }),
  ).pipe(Effect.map(({ helper }) => helper));
}

/** The endpoint a scoped helper announces on stdout; see helperEndpoint. */
export function awaitHelperEndpoint(helper: ChildProcess, home: string, options: HelperEndpointOptions): Effect.Effect<string, HostProcessError> {
  return Effect.tryPromise({ try: () => helperEndpoint(helper, home, options), catch: hostProcessError });
}

function assertPrivateIpcGrantsSync(plan: GrantPlan, cwd: string, home: string): void {
  const base = join(realpathSync(home), ".pi-ipc");
  const roots = [cwd, ...grantedPaths(plan, ["--allow"])];
  for (const path of roots) {
    const root = realpathSync(path);
    if (base === root || base.startsWith(`${root}${sep}`) || root === sep) {
      throw new GrantConflictError({ message: `Writable launcher grant covers private Pi IPC state: ${root}` });
    }
  }
}

/** Fail when a writable grant would cover private Pi IPC state. */
export function assertPrivateIpcGrants(plan: GrantPlan, cwd: string, home: string): Effect.Effect<void, SandboxError> {
  return attempt(() => assertPrivateIpcGrantsSync(plan, cwd, home));
}
