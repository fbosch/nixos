import { lstatSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";

function optionalEntry(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
}

export function sshClientArguments(home, environment) {
  const args = [];
  const directory = join(home, ".ssh");
  try {
    const entry = optionalEntry(directory);
    if (entry && !entry.isDirectory()) throw new Error("SSH client directory must be a real directory, not a symlink");
    if (entry) {
      for (const name of ["config", "known_hosts", "known_hosts2", "id_rsa.pub", "id_ed25519.pub", "id_ecdsa.pub"]) {
        const path = join(directory, name);
        const file = optionalEntry(path);
        if (!file) continue;
        // Mutable aliases could turn a public filename into a private-key read exception.
        if (file.isSymbolicLink()) {
          const target = realpathSync(path);
          if (!target.startsWith("/nix/store/") || !statSync(target).isFile()) {
            throw new Error(`SSH client file symlink must target an immutable Nix store file: ${path}`);
          }
        } else if (!file.isFile() || file.nlink !== 1) {
          throw new Error(`SSH client file must be a regular file without hard links: ${path}`);
        }
        // The default profile denies all of ~/.ssh; a read grant alone cannot lift that deny.
        args.push("--read-file", path, "--bypass-protection", path);
      }
    }
  } catch (error) {
    throw new Error(`Cannot grant SSH client access: ${error.message}`);
  }

  const socket = environment.SSH_AUTH_SOCK;
  if (socket) {
    try {
      if (!isAbsolute(socket)) throw new Error("must be absolute");
      if (!statSync(socket).isSocket()) throw new Error("must identify an existing Unix socket");
      // Authorize signing through the caller's existing agent, not access to private-key files.
      args.push("--allow-unix-socket", socket, "--bypass-protection", socket);
    } catch (error) {
      throw new Error(`Cannot grant SSH_AUTH_SOCK access: ${error.message}`);
    }
  }
  return args;
}

export function assertReadOnlySshGrants(args, cwd) {
  const values = flag => args.flatMap((part, index) => part === flag ? [args[index + 1]] : []);
  const exemptions = new Set(values("--bypass-protection"));
  const files = values("--read-file").filter(path => exemptions.has(path));
  if (files.length === 0) return;
  const roots = [cwd, ...values("--allow")].flatMap(path => optionalEntry(path) ? [path, realpathSync(path)] : [path]);
  for (const file of files) {
    const targets = [file, realpathSync(file), join(realpathSync(dirname(file)), basename(file))];
    for (const root of roots) {
      if (targets.some(path => path === root || path.startsWith(root.endsWith(sep) ? root : `${root}${sep}`))) {
        // Nono grants are additive: an overlapping writable root would defeat this read-only exception.
        throw new Error(`SSH client file overlaps a writable launcher grant: ${file} (${root})`);
      }
    }
  }
}
