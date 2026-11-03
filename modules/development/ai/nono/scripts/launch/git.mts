import { existsSync, lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { existingDirectory, within } from "../shared/paths.mts";
import type { ErrnoError } from "../shared/types.mts";

/** Git metadata that a checkout needs writable, and how the checkout is registered. */
export interface GitMetadata {
  /** Writable grants for metadata outside the checkout; empty when it lies inside cwd. */
  roots: string[];
  /** The checkout's own Git directory: the repository, or `worktrees/<name>` for a worktree. */
  directory?: string;
  commonDirectory?: string;
  checkoutRoot?: string;
  worktree?: boolean;
}

export function gitMetadata(cwd: string, home: string): GitMetadata {
  const canonicalCwd = realpathSync(cwd);
  const canonicalHome = existingDirectory(home) ?? resolve(home);
  for (let root = canonicalCwd; ; root = dirname(root)) {
    const marker = join(root, ".git");
    let entry;
    try {
      entry = lstatSync(marker);
    } catch (error) {
      if ((error as ErrnoError).code !== "ENOENT") throw new Error(`Cannot inspect Git metadata at ${marker}: ${(error as Error).message}`);
      if (root === dirname(root)) return { roots: [] };
      continue;
    }
    try {
      let metadata: string;
      let gitDir: string | undefined;
      if (entry.isDirectory()) {
        metadata = realpathSync(marker);
      } else if (entry.isFile()) {
        const pointer = /^gitdir: ([^\r\n\x00]+)\r?\n?$/.exec(readFileSync(marker, "utf8"));
        if (!pointer) throw new Error("Invalid .git worktree pointer");
        gitDir = realpathSync(resolve(root, pointer[1]!));
        if (!statSync(gitDir).isDirectory()) throw new Error("Worktree Git path is not a directory");
        const readPath = (name: string) => {
          const path = readFileSync(join(gitDir!, name), "utf8").replace(/\r?\n$/, "");
          if (!path || /[\x00-\x1f\x7f]/.test(path)) throw new Error(`Invalid worktree ${name} path`);
          return resolve(gitDir!, path);
        };
        metadata = realpathSync(readPath("commondir"));
        if (!statSync(metadata).isDirectory()) throw new Error("Shared Git path is not a directory");
        // A mutable .git pointer must not authorize arbitrary directories or another checkout's metadata.
        if (dirname(gitDir) !== join(metadata, "worktrees") || realpathSync(readPath("gitdir")) !== marker) {
          throw new Error("Git worktree registration does not match this checkout");
        }
        if (!statSync(join(metadata, "HEAD")).isFile() ||
            !statSync(join(metadata, "objects")).isDirectory() || !statSync(join(metadata, "refs")).isDirectory()) {
          throw new Error("Shared directory is not Git repository metadata");
        }
      } else {
        throw new Error(".git must be a directory or a regular worktree pointer file");
      }
      if (within(canonicalHome, metadata) || within(root, metadata)) {
        throw new Error("Git metadata must not resolve to the home directory or a checkout ancestor");
      }
      // Indexes, locks, refs and objects need writes; granting only worktrees/<name> is insufficient.
      return {
        roots: within(metadata, canonicalCwd) ? [] : [metadata],
        directory: gitDir ?? metadata,
        commonDirectory: metadata,
        checkoutRoot: root,
        worktree: gitDir !== undefined,
      };
    } catch (error) {
      throw new Error(`Cannot resolve Git metadata from ${marker}: ${(error as Error).message}`);
    }
  }
}

export function pairedRepositoryRoots(home: string): string[] {
  // These exceptions are packaged by Nix, never selected by mutable reference names or settings.
  const roots = ["dotfiles", "nixos"].map((name) => existingDirectory(join(home, name))).filter(Boolean) as string[];
  if (roots.length === 0) return [];
  const canonicalHome = realpathSync(home);
  if (roots.some((root) => within(canonicalHome, root))) {
    throw new Error("Paired repository paths must not resolve to the home directory or an ancestor.");
  }
  return roots;
}

export function writableReferenceRoots(cwd: string, home: string, metadata: GitMetadata): string[] {
  const roots = pairedRepositoryRoots(home);
  const canonicalCwd = realpathSync(cwd);
  if (roots.some(root => within(canonicalCwd, root))) return roots;
  if (!metadata.worktree) return [];
  // Only a registered worktree of a fixed configuration repository receives editing authority.
  for (const root of roots) {
    if (!existsSync(join(root, ".git"))) continue;
    const trusted = gitMetadata(root, home);
    if (trusted.checkoutRoot === root && trusted.commonDirectory === metadata.commonDirectory) return roots;
  }
  return [];
}
