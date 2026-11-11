import * as Effect from "effect/Effect";
import { spawnSync } from "node:child_process";
import { realpathSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";
import { existingFile, optionalLstat } from "../shared/paths.mts";
import type { Environment, ErrnoError } from "../shared/types.mts";
import { GrantConflictError, InvalidConfigError, LaunchPrerequisiteError, type SandboxError, UnsafeFileError, attempt } from "../shared/errors.mts";
import { sandboxPolicy } from "../shared/sandbox-policy.mts";
import { grant, grantedPaths, type Grant, type GrantPlan } from "../shared/grant-plan.mts";

function sshClientGrantsSync(home: string, environment: Environment): Grant[] {
  const grants: Grant[] = [];
  const directory = join(home, ".ssh");
  try {
    const entry = optionalLstat(directory);
    if (entry && !entry.isDirectory()) throw new UnsafeFileError({ message: "SSH client directory must be a real directory, not a symlink" });
    if (entry) {
      for (const name of sandboxPolicy.ssh.publicFiles) {
        const path = join(directory, name);
        const file = optionalLstat(path);
        if (!file) continue;
        // Mutable aliases could turn a public filename into a private-key read exception.
        if (file.isSymbolicLink()) {
          const target = realpathSync(path);
          if (!target.startsWith("/nix/store/") || !statSync(target).isFile()) {
            throw new UnsafeFileError({ message: `SSH client file symlink must target an immutable Nix store file: ${path}` });
          }
        } else if (!file.isFile() || file.nlink !== 1) {
          throw new UnsafeFileError({ message: `SSH client file must be a regular file without hard links: ${path}` });
        }
        // The default profile denies all of ~/.ssh; a read grant alone cannot lift that deny.
        grants.push(grant("--read-file", path), grant("--bypass-protection", path));
      }
    }
  } catch (error) {
    throw new UnsafeFileError({ message: `Cannot grant SSH client access: ${(error as Error).message}` });
  }

  // The agent signs as the host user; only the launcher's host-side opt-in may expose it.
  const socket = environment.PI_NONO_SSH_AGENT === "1" ? environment.SSH_AUTH_SOCK : undefined;
  if (socket) {
    try {
      if (!isAbsolute(socket)) throw new InvalidConfigError({ message: "must be absolute" });
      if (!statSync(socket).isSocket()) throw new LaunchPrerequisiteError({ message: "must identify an existing Unix socket" });
      // Authorize signing through the caller's existing agent, not access to private-key files.
      grants.push(grant("--allow-unix-socket", socket), grant("--bypass-protection", socket));
    } catch (error) {
      if ((error as ErrnoError).code === "ENOENT") {
        console.warn(`pi sandbox launch: SSH_AUTH_SOCK socket is missing (${JSON.stringify(socket)}); continuing without SSH agent access.`);
      } else {
        throw new LaunchPrerequisiteError({ message: `Cannot grant SSH_AUTH_SOCK access: ${(error as Error).message}` });
      }
    }
  }
  return grants;
}

/** Read-only grants for public SSH client files, plus the agent socket when the host opted in. */
export function sshClientGrants(home: string, environment: Environment): Effect.Effect<Grant[], SandboxError> {
  return attempt(() => sshClientGrantsSync(home, environment));
}

function assertReadOnlySshGrantsSync(plan: GrantPlan, cwd: string): void {
  const exemptions = new Set(grantedPaths(plan, ["--bypass-protection"]));
  const files = grantedPaths(plan, ["--read-file"]).filter(path => exemptions.has(path));
  if (files.length === 0) return;
  const roots = [cwd, ...grantedPaths(plan, ["--allow"]), ...grantedPaths(plan, ["--allow-file"])].flatMap(path => optionalLstat(path) ? [path, realpathSync(path)] : [path]);
  for (const file of files) {
    const targets = [file, realpathSync(file), join(realpathSync(dirname(file)), basename(file))];
    for (const root of roots) {
      if (targets.some(path => path === root || path.startsWith(root.endsWith(sep) ? root : `${root}${sep}`))) {
        // Nono grants are additive: an overlapping writable root would defeat this read-only exception.
        throw new GrantConflictError({ message: `SSH client file overlaps a writable launcher grant: ${file} (${root})` });
      }
    }
  }
}

/** Fail when a writable grant would cover an SSH file that must stay read-only. */
export function assertReadOnlySshGrants(plan: GrantPlan, cwd: string): Effect.Effect<void, SandboxError> {
  return attempt(() => assertReadOnlySshGrantsSync(plan, cwd));
}

// Sandboxed SSH and Git signing only reach keys through the agent; the private key file stays denied.
// Load configured keys on the host first, while the launcher still owns the terminal for a passphrase prompt.
export type SshIdentityResult = "skipped" | "loaded" | "added" | "failed";

export function ensureSshIdentity(environment: Environment, home: string, sshAdd: string | undefined, { run = spawnSync, interactive = process.stdin.isTTY === true }: { run?: typeof spawnSync; interactive?: boolean } = {}): SshIdentityResult {
  const socket = environment.SSH_AUTH_SOCK;
  if (!interactive || !socket || !sshAdd || !isAbsolute(sshAdd)) return "skipped";
  const keys = sandboxPolicy.ssh.agentIdentities.map(name => join(home, ".ssh", name)).filter(existingFile);
  if (keys.length === 0) return "skipped";
  const env = { SSH_AUTH_SOCK: socket, HOME: home };
  // ssh-add -l exits 1 for an empty agent and 2 when no agent is reachable.
  const listed = run(sshAdd, ["-l"], { env, stdio: "ignore", timeout: 5000 });
  if (listed.status !== 0 && listed.status !== 1) return "skipped";
  let result: SshIdentityResult = "loaded";
  for (const key of keys) {
    // -T checks this public key with the agent, not just whether any identity is loaded.
    const publicKey = `${key}.pub`;
    if (existingFile(publicKey) && run(sshAdd, ["-T", publicKey], { env, stdio: "ignore", timeout: 5000 }).status === 0) continue;
    const added = run(sshAdd, [key], { env, stdio: "inherit", timeout: 120_000 });
    if (added.status === 0) {
      if (result !== "failed") result = "added";
      continue;
    }
    console.warn(`pi sandbox launch: ssh-add did not load ~/.ssh/${basename(key)}; SSH operations requiring this identity will fail inside Pi.`);
    result = "failed";
  }
  return result;
}
