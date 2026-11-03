import * as Effect from "effect/Effect";
import { existsSync, lstatSync, readFileSync, realpathSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { existingDirectory, within } from "../shared/paths.mts";
import type { ErrnoError } from "../shared/types.mts";
import { InvalidConfigError, type SandboxError, UnsafeFileError, attempt } from "../shared/errors.mts";
import { sandboxPolicy } from "../shared/sandbox-policy.mts";

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

function gitMetadataSync(cwd: string, home: string): GitMetadata {
  const canonicalCwd = realpathSync(cwd);
  const canonicalHome = existingDirectory(home) ?? resolve(home);
  for (let root = canonicalCwd; ; root = dirname(root)) {
    const marker = join(root, ".git");
    let entry;
    try {
      entry = lstatSync(marker);
    } catch (error) {
      if ((error as ErrnoError).code !== "ENOENT") throw new UnsafeFileError({ message: `Cannot inspect Git metadata at ${marker}: ${(error as Error).message}` });
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
        if (!pointer) throw new InvalidConfigError({ message: "Invalid .git worktree pointer" });
        gitDir = realpathSync(resolve(root, pointer[1]!));
        if (!statSync(gitDir).isDirectory()) throw new UnsafeFileError({ message: "Worktree Git path is not a directory" });
        const readPath = (name: string) => {
          const path = readFileSync(join(gitDir!, name), "utf8").replace(/\r?\n$/, "");
          if (!path || /[\x00-\x1f\x7f]/.test(path)) throw new InvalidConfigError({ message: `Invalid worktree ${name} path` });
          return resolve(gitDir!, path);
        };
        metadata = realpathSync(readPath("commondir"));
        if (!statSync(metadata).isDirectory()) throw new UnsafeFileError({ message: "Shared Git path is not a directory" });
        // A mutable .git pointer must not authorize arbitrary directories or another checkout's metadata.
        if (dirname(gitDir) !== join(metadata, "worktrees") || realpathSync(readPath("gitdir")) !== marker) {
          throw new UnsafeFileError({ message: "Git worktree registration does not match this checkout" });
        }
        if (!statSync(join(metadata, "HEAD")).isFile() ||
            !statSync(join(metadata, "objects")).isDirectory() || !statSync(join(metadata, "refs")).isDirectory()) {
          throw new UnsafeFileError({ message: "Shared directory is not Git repository metadata" });
        }
      } else {
        throw new UnsafeFileError({ message: ".git must be a directory or a regular worktree pointer file" });
      }
      if (within(canonicalHome, metadata) || within(root, metadata)) {
        throw new UnsafeFileError({ message: "Git metadata must not resolve to the home directory or a checkout ancestor" });
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
      throw new UnsafeFileError({ message: `Cannot resolve Git metadata from ${marker}: ${(error as Error).message}` });
    }
  }
}

/** Resolve and validate the Git metadata that a checkout under `cwd` needs writable. */
export function gitMetadata(cwd: string, home: string): Effect.Effect<GitMetadata, SandboxError> {
  return attempt(() => gitMetadataSync(cwd, home));
}

function pairedRepositoryRootsSync(home: string): string[] {
  // These exceptions are packaged by Nix, never selected by mutable reference names or settings.
  const roots = sandboxPolicy.exceptions.configurationRepositories.map((name) => existingDirectory(join(home, name))).filter(Boolean) as string[];
  if (roots.length === 0) return [];
  const canonicalHome = realpathSync(home);
  if (roots.some((root) => within(canonicalHome, root))) {
    throw new UnsafeFileError({ message: "Paired repository paths must not resolve to the home directory or an ancestor." });
  }
  return roots;
}

/** The fixed configuration repositories (`~/dotfiles`, `~/nixos`) that may edit Pi setup. */
export function pairedRepositoryRoots(home: string): Effect.Effect<string[], SandboxError> {
  return attempt(() => pairedRepositoryRootsSync(home));
}

function writableReferenceRootsSync(cwd: string, home: string, metadata: GitMetadata): string[] {
  const roots = pairedRepositoryRootsSync(home);
  const canonicalCwd = realpathSync(cwd);
  if (roots.some(root => within(canonicalCwd, root))) return roots;
  if (!metadata.worktree) return [];
  // Only a registered worktree of a fixed configuration repository receives editing authority.
  for (const root of roots) {
    if (!existsSync(join(root, ".git"))) continue;
    const trusted = gitMetadataSync(root, home);
    if (trusted.checkoutRoot === root && trusted.commonDirectory === metadata.commonDirectory) return roots;
  }
  return [];
}

/** Configuration roots that become writable because `cwd` is one of them or a registered worktree. */
export function writableReferenceRoots(cwd: string, home: string, metadata: GitMetadata): Effect.Effect<string[], SandboxError> {
  return attempt(() => writableReferenceRootsSync(cwd, home, metadata));
}
