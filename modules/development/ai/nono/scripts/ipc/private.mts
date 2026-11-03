import * as Effect from "effect/Effect";
import { lstatSync, mkdirSync, mkdtempSync, realpathSync, statSync } from "node:fs";
import type { ChildProcess } from "node:child_process";
import { join, sep } from "node:path";
import { GrantConflictError, type SandboxError, UnsafeFileError, attempt } from "../shared/errors.mts";
import type { ErrnoError } from "../shared/types.mts";

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

export function helperEndpoint(helper: ChildProcess, home: string, { name, timeoutMs, diagnostics, hint }: HelperEndpointOptions): Promise<string> {
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

function assertPrivateIpcGrantsSync(args: readonly string[], cwd: string, home: string): void {
  const base = join(realpathSync(home), ".pi-ipc");
  const roots = [cwd, ...args.flatMap((part, index) => part === "--allow" ? [args[index + 1]!] : [])];
  for (const path of roots) {
    const root = realpathSync(path);
    if (base === root || base.startsWith(`${root}${sep}`) || root === sep) {
      throw new GrantConflictError({ message: `Writable launcher grant covers private Pi IPC state: ${root}` });
    }
  }
}

/** Fail when a writable grant would cover private Pi IPC state. */
export function assertPrivateIpcGrants(args: readonly string[], cwd: string, home: string): Effect.Effect<void, SandboxError> {
  return attempt(() => assertPrivateIpcGrantsSync(args, cwd, home));
}
