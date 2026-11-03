import { existsSync, lstatSync, readFileSync, realpathSync, statSync, type Stats } from "node:fs";
import { join, sep } from "node:path";
import type { ErrnoError, JsonValue } from "./types.mts";
import { InvalidConfigError, UnsafeFileError } from "./errors.mts";

export function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** True when `path` is `root` or lies beneath it. Both paths must already be normalized. */
export function within(path: string, root: string): boolean {
  return root === sep || path === root || path.startsWith(`${root}${sep}`);
}

/** The canonical directory, `undefined` when missing; throws when the path is not a directory. */
export function existingDirectory(path: string): string | undefined {
  if (!existsSync(path)) return undefined;
  const canonical = realpathSync(path);
  if (!statSync(canonical).isDirectory()) throw new UnsafeFileError({ message: `Not a directory: ${path}` });
  return canonical;
}

export function existingFile(path: string): boolean {
  return existsSync(path) && statSync(path).isFile();
}

/** `lstat` that returns `undefined` for a missing path instead of throwing. */
export function optionalLstat(path: string): Stats | undefined {
  try {
    return lstatSync(path);
  } catch (error) {
    if ((error as ErrnoError).code === "ENOENT") return undefined;
    throw error;
  }
}

/** Parse a JSON file, `undefined` when missing. Settings files may carry a UTF-8 BOM. */
export function readJsonFile(path: string, label: string): JsonValue | undefined {
  if (!existsSync(path)) return undefined;
  try {
    return JSON.parse(readFileSync(path, "utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    throw new InvalidConfigError({ message: `Cannot load ${label} from ${path}: ${(error as Error).message}` });
  }
}

/** Expand a leading `~` the way Pi settings do; other paths are returned unchanged. */
export function expandTilde(path: string, home: string): string {
  if (path === "~") return home;
  return path.startsWith("~/") ? join(home, path.slice(2)) : path;
}
