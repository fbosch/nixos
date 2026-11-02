import { lstatSync, mkdirSync, mkdtempSync, realpathSync } from "node:fs";
import { join, sep } from "node:path";

/** The private, user-owned IPC state directory; no sandbox grant may cover it. */
export function privateIpcBase(home) {
  const base = join(realpathSync(home), ".pi-ipc");
  try {
    mkdirSync(base, { mode: 0o700 });
  } catch (error) {
    if (error.code !== "EEXIST") throw error;
  }
  const entry = lstatSync(base);
  if (!entry.isDirectory() || entry.uid !== process.getuid() || (entry.mode & 0o077) !== 0) {
    throw new Error("Pi IPC state must be a private, user-owned directory without symlinks");
  }
  return base;
}

export function privateIpcDirectory(home, prefix) {
  return mkdtempSync(join(privateIpcBase(home), prefix));
}
export function assertPrivateIpcGrants(args, cwd, home) {
  const base = join(realpathSync(home), ".pi-ipc");
  const roots = [cwd, ...args.flatMap((part, index) => part === "--allow" ? [args[index + 1]] : [])];
  for (const path of roots) {
    const root = realpathSync(path);
    if (base === root || base.startsWith(`${root}${sep}`) || root === sep) {
      throw new Error(`Writable launcher grant covers private Pi IPC state: ${root}`);
    }
  }
}
