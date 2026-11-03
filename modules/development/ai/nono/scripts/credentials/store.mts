// Pi's credential files live in a host-only store that no sandbox grant covers. The agent
// directory keeps relative symlinks with the original names, so Pi and auth-profiles use the same
// paths in every mode, and a sandbox that can list or read the agent directory cannot follow the
// links: Landlock and Seatbelt check the resolved file.
import { closeSync, chmodSync, fsyncSync, linkSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmdirSync, statSync, symlinkSync, unlinkSync, writeSync, type Stats } from "node:fs";
import { spawnSync } from "node:child_process";
import { basename, dirname, join, relative } from "node:path";
import type { ErrnoError } from "../shared/types.mts";

/** Why migrateFile left a credential where it was, or that it moved. */
type MigrationOutcome = "missing" | "linked" | "foreign" | "locked" | "conflict" | "changed" | "migrated";

export interface ProcessEntry {
  pid: number;
  argv: string[];
}

const PROFILE_FILE = /^[A-Za-z0-9._-]+\.json$/;
// Matches proper-lockfile's default stale period with margin; a crashed Pi leaves its lock behind.
const STALE_LOCK_MS = 60_000;

/** Fixed below the home directory, so a project environment cannot relocate it. */
export function credentialStoreDirectory(home: string): string {
  return join(realpathSync(home), ".local", "share", "pi-credentials");
}

function privateDirectory(path: string): void {
  mkdirSync(path, { recursive: true, mode: 0o700 });
  const entry = lstatSync(path);
  if (!entry.isDirectory() || entry.uid !== process.getuid!()) {
    throw new Error(`Pi credential store must be a user-owned directory without symlinks: ${path}`);
  }
  if ((entry.mode & 0o077) !== 0) chmodSync(path, 0o700);
}

function missing(error: unknown): boolean {
  return (error as ErrnoError | undefined)?.code === "ENOENT";
}

function writePrivateFile(path: string, content: string | Buffer): void {
  const temporary = `${path}.migrate-${process.pid}`;
  const descriptor = openSync(temporary, "wx", 0o600);
  try {
    // writeSync accepts either type; its separate overloads only reject the union.
    writeSync(descriptor, content as string);
    fsyncSync(descriptor);
  } finally {
    closeSync(descriptor);
  }
  try {
    // A link fails if another launch created the file first; the caller rechecks it.
    linkSync(temporary, path);
  } finally {
    unlinkSync(temporary);
  }
}

function replaceWithLink(path: string, target: string): void {
  const temporary = join(dirname(path), `.${basename(path)}.migrate-${process.pid}`);
  symlinkSync(relative(dirname(path), target), temporary);
  renameSync(temporary, path);
}

/** Takes Pi's own lock for `path` (proper-lockfile's `<path>.lock` directory). */
function lock(path: string): (() => void) | undefined {
  const directory = `${path}.lock`;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      mkdirSync(directory);
      return () => rmdirSync(directory);
    } catch (error) {
      if ((error as ErrnoError).code !== "EEXIST") throw error;
      let age: number;
      try { age = Date.now() - statSync(directory).mtimeMs; } catch (statError) { if (!missing(statError)) throw statError; continue; }
      if (age < STALE_LOCK_MS) return undefined;
      rmdirSync(directory);
    }
  }
  return undefined;
}

/** Moves one credential file into the store, or reports why it stays in place. */
function migrateFile(path: string, target: string, warnings: string[]): MigrationOutcome {
  let entry: Stats;
  try { entry = lstatSync(path); } catch (error) { if (missing(error)) return "missing"; throw error; }
  if (entry.isSymbolicLink()) {
    let resolved: string | undefined;
    try { resolved = realpathSync(path); } catch { resolved = undefined; }
    if (resolved === target) return "linked";
    warnings.push(`${path} links to ${resolved ?? "a missing file"}, not the Pi credential store; leaving it in place.`);
    return "foreign";
  }
  if (!entry.isFile() || entry.nlink !== 1) {
    warnings.push(`${path} is not a regular file without hard links; leaving it in place.`);
    return "foreign";
  }
  const release = lock(path);
  if (!release) {
    warnings.push(`${path} is locked by another Pi process; it moves to the credential store on a later launch.`);
    return "locked";
  }
  try {
    const content = readFileSync(path);
    let existing: Buffer | undefined;
    try { existing = readFileSync(target); } catch (error) { if (!missing(error)) throw error; }
    if (existing !== undefined && !existing.equals(content)) {
      warnings.push(`${path} differs from ${target}; leaving both in place. Keep the one you want, delete the other, and relaunch.`);
      return "conflict";
    }
    if (existing === undefined) writePrivateFile(target, content);
    // Writers that ignore the lock could have changed the file while it was copied.
    if (!readFileSync(path).equals(content)) {
      if (existing === undefined) unlinkSync(target);
      warnings.push(`${path} changed during migration; it moves to the credential store on a later launch.`);
      return "changed";
    }
    replaceWithLink(path, target);
    return "migrated";
  } finally {
    release();
  }
}

/**
 * Moves the agent directory's auth.json and auth-profiles/*.json into the credential store and
 * leaves symlinks. Idempotent; files that cannot move safely stay in place with a warning, so an
 * existing setup keeps working unchanged.
 */
export function migrateCredentialStore(home: string, agentDir: string): { store: string; warnings: string[] } {
  const warnings: string[] = [];
  const store = credentialStoreDirectory(home);
  const root = realpathSync(agentDir);
  privateDirectory(store);
  privateDirectory(join(store, "auth-profiles"));

  const auth = join(root, "auth.json");
  const storedAuth = join(store, "auth.json");
  let hasAuth = true;
  try { lstatSync(auth); } catch (error) { if (!missing(error)) throw error; hasAuth = false; }
  if (!hasAuth) {
    // Pi would otherwise create a fresh regular auth.json beside the other agent files.
    try { lstatSync(storedAuth); } catch (error) { if (!missing(error)) throw error; writePrivateFile(storedAuth, "{}"); }
    replaceWithLink(auth, storedAuth);
  } else {
    migrateFile(auth, storedAuth, warnings);
  }

  const profiles = join(root, "auth-profiles");
  let entry: Stats | undefined;
  try { entry = lstatSync(profiles); } catch (error) { if (!missing(error)) throw error; }
  if (entry?.isSymbolicLink()) {
    warnings.push(`${profiles} is a symlink; leaving profile credentials in place.`);
  } else if (entry?.isDirectory()) {
    for (const name of readdirSync(profiles).sort()) {
      if (PROFILE_FILE.test(name)) migrateFile(join(profiles, name), join(store, "auth-profiles", name), warnings);
    }
  }
  return { store, warnings };
}

/**
 * Process ids of running nono sandboxes. Sessions started before migration were granted the old
 * file paths; moving credentials under them would cut off their logins and token refreshes.
 * Undefined when the process list cannot be read.
 */
export function runningSandboxes(platform: NodeJS.Platform = process.platform, listProcesses: (platform: NodeJS.Platform) => ProcessEntry[] | undefined = defaultProcessList): number[] | undefined {
  const processes = listProcesses(platform);
  if (processes === undefined) return undefined;
  return processes
    .filter(({ pid, argv }) => pid !== process.pid && basename(argv[0] ?? "") === "nono" && argv[1] === "run")
    .map(({ pid }) => pid);
}

function defaultProcessList(platform: NodeJS.Platform): ProcessEntry[] | undefined {
  if (platform === "linux") {
    let entries: string[];
    try { entries = readdirSync("/proc"); } catch { return undefined; }
    return entries.filter((name) => /^\d+$/.test(name)).flatMap((name) => {
      try {
        return [{ pid: Number(name), argv: readFileSync(join("/proc", name, "cmdline"), "utf8").split("\0").filter(Boolean) }];
      } catch {
        return [];
      }
    });
  }
  const result = spawnSync("/bin/ps", ["-axo", "pid=,command="], { encoding: "utf8", timeout: 5000 });
  if (result.status !== 0 || typeof result.stdout !== "string") return undefined;
  return result.stdout.split("\n").flatMap((line) => {
    const match = /^\s*(\d+)\s+(.*)$/.exec(line);
    // shortcut: ps joins argv with spaces; argv[0] and argv[1] of nono contain none.
    return match ? [{ pid: Number(match[1]), argv: match[2]!.split(" ") }] : [];
  });
}

/** Credential files Pi would use that still live outside the store, as regular files. */
export function credentialFilesOutsideStore(roots: readonly string[]): string[] {
  const paths: string[] = [];
  for (const root of roots) {
    const candidates = [join(root, "auth.json")];
    try {
      for (const name of readdirSync(join(root, "auth-profiles"))) if (PROFILE_FILE.test(name)) candidates.push(join(root, "auth-profiles", name));
    } catch (error) { if (!missing(error) && (error as ErrnoError).code !== "ENOTDIR") throw error; }
    for (const path of candidates) {
      try { if (lstatSync(path).isFile()) paths.push(path); } catch (error) { if (!missing(error)) throw error; }
    }
  }
  return paths;
}
