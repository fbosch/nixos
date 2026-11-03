import * as Effect from "effect/Effect";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { credentialProxySession } from "../../credentials/proxy.mts";
import { credentialFilesOutsideStore } from "../../credentials/store.mts";
import { shellProtection } from "../../protection/shell.mts";
import { attempt } from "../../shared/errors.mts";
import { grant } from "../../shared/grant-plan.mts";
import { existingDirectory } from "../../shared/paths.mts";
import { sandboxPolicy } from "../../shared/sandbox-policy.mts";
import type { ExitResult } from "../../shared/types.mts";
import type { Confinement } from "./confinement.mts";

// sops-nix Home Manager decrypts user secrets into %r/secrets.d and links the active generation from %r/secrets.
const runtimeSecretEntries = sandboxPolicy.filesystem.runtimeDirectory.secrets;
// Sandboxed tools cannot create top-level runtime entries, so create their directories before granting them.
const runtimeServiceDirectories = sandboxPolicy.filesystem.runtimeDirectory.services;

/** Landlock: protected paths stay outside every writable grant, because a grant cannot exclude a child. */
export const linuxConfinement: Confinement = {
  runtimeDirectoryGrants: (runtime) => {
    for (const name of runtimeServiceDirectories) mkdirSync(join(runtime, name), { recursive: true, mode: 0o700 });
    // Grant top-level entries instead of the root. Sockets need no grant while AF_UNIX mediation is
    // off; symlinks are skipped so they cannot redirect a grant.
    return readdirSync(runtime, { withFileTypes: true }).flatMap((entry) => {
      if (runtimeSecretEntries.includes(entry.name)) return [];
      const path = join(runtime, entry.name);
      if (entry.isDirectory()) return [grant("--allow", path)];
      return entry.isFile() ? [grant("--allow-file", path)] : [];
    });
  },
  // grim and other Wayland clients allocate buffers with shm_open; its flat names cannot be scoped per tool.
  // Both IPC profiles permit native screenshots and the accompanying access to unrelated same-user shared memory.
  sharedMemoryGrants: () => {
    const sharedMemory = existingDirectory("/dev/shm");
    return sharedMemory === undefined ? [] : [grant("--allow", sharedMemory)];
  },
  runtimeSecrets: (environment) => Effect.gen(function* () {
    const runtime = environment.XDG_RUNTIME_DIR ? yield* attempt(() => existingDirectory(environment.XDG_RUNTIME_DIR!)) : undefined;
    if (runtime === undefined) return undefined;
    return runtimeSecretEntries.map((name) => join(runtime, name)).filter((path) => existsSync(path));
  }),
  protections: ({ home, environment, agent, approvals, credentialPaths }) => Effect.gen(function* () {
    const shellPaths = (yield* attempt(() => existingDirectory(home))) !== undefined ? (yield* shellProtection(home, environment)).protectedPaths : [];
    const hostOnly = [...shellPaths, ...agent.protectedPaths, approvals, ...credentialPaths];
    return { guarded: hostOnly, splitAround: hostOnly, splitCwd: true };
  }),
  // Landlock cannot hide regular files inside a readable agent directory; only store links are safe.
  exposedCredentials: (agentDirectories) => credentialFilesOutsideStore(agentDirectories),
  runFlags: [],
  run: ({ nono, profile, nonoProfile, command, environment }) => {
    if (nonoProfile.network?.credentials?.length) return credentialProxySession(nono, profile, command, environment, { sandboxed: true });
    return Effect.sync((): ExitResult => spawnSync(command[0]!, command.slice(1), { stdio: "inherit", env: environment }));
  },
};
