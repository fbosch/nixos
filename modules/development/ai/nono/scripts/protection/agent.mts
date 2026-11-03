import { existsSync, lstatSync, mkdirSync, readdirSync, realpathSync } from "node:fs";
import { isAbsolute, join } from "node:path";
import { canonicalCredentialPath } from "../credentials/grants.mts";
import { credentialStoreDirectory } from "../credentials/store.mts";
import { within } from "../shared/paths.mts";
import type { Environment, ErrnoError, NonoProfile } from "../shared/types.mts";
import { resolveComponents } from "./resolve.mts";

/** Paths that agentProtection keeps read-only, and the agent data that stays writable. */
export interface AgentProtection {
  protectedPaths: string[];
  runtimePaths: string[];
  authFiles: string[];
}

function storeDirectory(home: string): string | undefined {
  try { return credentialStoreDirectory(home); } catch { return undefined; }
}

// These are data stores, not Pi resource-discovery or package-installation directories.
// pi-fff stores LMDB frecency/history beneath agent/fff when no editor database exists.
const runtimeDirectories = new Set(["sessions", "cache", "session-history", "tasks", "auth-profiles", "fff"]);
const requiredControls = ["settings.json", "extensions", "npm", "git", "lib", "mcp.json", "models.json", "trust.json"];
// Every entry is checked for symlinks and hard links. Installed extension packages (node_modules,
// npm) in the default and configured agent directories can exceed 100000 entries together; a full
// scan of about 120000 entries takes about two seconds on rvn-mac.
const MAX_CONTROL_ENTRIES = 300000;

export function agentDirectories(home: string, agentDir: string): string[] {
  const roots = [...new Set([join(home, ".pi", "agent"), agentDir].filter(path => existsSync(path)).map(path => realpathSync(path)))];
  const canonicalHome = existsSync(home) ? realpathSync(home) : home;
  if (roots.some(root => within(canonicalHome, root))) throw new Error("Pi agent directory must not resolve to the home directory or an ancestor");
  return roots;
}

/**
 * Credential stores in every agent directory, as given and canonical: auth.json (with its lock
 * files) and auth-profiles/. In executor mode the sandbox reaches them only through the executor.
 */
export function agentCredentialPaths(home: string, agentDir: string): string[] {
  const paths = new Set<string>();
  // Migrated credentials live in the store; Seatbelt and Landlock check the resolved file.
  const store = storeDirectory(home);
  if (store !== undefined) paths.add(store);
  for (const root of agentDirectories(home, agentDir)) {
    for (const name of ["auth.json", "auth-profiles"]) {
      const path = join(root, name);
      paths.add(path);
      if (existsSync(path)) paths.add(realpathSync(path));
    }
  }
  return [...paths];
}

export function agentProtection(home: string, agentDir: string, environment: Environment = {}, profile: NonoProfile = {}, platform: NodeJS.Platform = process.platform): AgentProtection {
  const roots = agentDirectories(home, agentDir);
  const canonicalHome = existsSync(home) ? realpathSync(home) : home;
  // These broad Linux default grants cannot be narrowed by splitting launcher arguments.
  const systemTemporary = canonicalCredentialPath("/tmp", "Pi control");
  const inheritedWrites = [join(home, ".cache"), ...(!within(canonicalHome, systemTemporary) ? [systemTemporary] : [])];
  for (const field of ["allow", "write", "allow_file", "write_file"] as const) {
    for (const entry of profile.filesystem?.[field] ?? []) {
      if (typeof entry !== "string" && entry.when && entry.when !== (platform === "darwin" ? "macos" : platform)) continue;
      const template = typeof entry === "string" ? entry : entry.path;
      inheritedWrites.push(template.replace(/\$(?:\{(\w+)\}|(\w+))/g, (_, braced: string | undefined, bare: string | undefined) => {
        const name = braced || bare!;
        const value = name === "HOME" ? home : environment[name];
        if (!value) throw new Error(`Missing Pi profile path variable: ${name}`);
        return value;
      }));
    }
  }
  // Seatbelt can subtract write denials from broad grants; Landlock must reject such overlaps.
  const fixedWrites = platform === "linux" ? inheritedWrites.map(path => canonicalCredentialPath(path, "Pi control")) : [];
  const protectedPaths = new Set<string>();
  const runtimePaths = new Set<string>();
  const authFiles = new Set<string>();
  const visited = new Set<string>();
  let entries = 0;

  function canonicalPath(path: string): string {
    if (!isAbsolute(path)) throw new Error(`Pi control path must be absolute: ${path}`);
    // Include dangling Stow targets: future creation must not create an unprotected resource.
    return resolveComponents(path, "Pi control", { onLink: link => protectedPaths.add(link) });
  }
  function protect(path: string): void {
    protectedPaths.add(path);
    const canonical = canonicalPath(path);
    if (within(canonicalHome, canonical)) throw new Error(`Pi control path resolves to a home ancestor: ${path}`);
    if (fixedWrites.some(root => within(canonical, root) || within(root, canonical))) {
      throw new Error(`Pi control path overlaps a writable profile or default-group grant: ${path}`);
    }
    protectedPaths.add(canonical);
    scan(canonical);
  }

  function scan(path: string): void {
    if (visited.has(path) || path.startsWith("/nix/store/")) return;
    visited.add(path);
    if (++entries > MAX_CONTROL_ENTRIES) throw new Error(`Pi control protection exceeds ${MAX_CONTROL_ENTRIES} entries`);
    let entry;
    try { entry = lstatSync(path); }
    catch (error) { if ((error as ErrnoError).code === "ENOENT") return; throw error; }
    if (entry.isSymbolicLink()) {
      protect(path);
    } else if (entry.isDirectory()) {
      for (const name of readdirSync(path)) scan(join(path, name));
    } else if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error(`Pi control file must be regular and not hard-linked: ${path}`);
    }
  }

  for (const root of roots) {
    for (const name of requiredControls) protect(join(root, name));
    for (const name of readdirSync(root)) {
      const path = join(root, name);
      if (runtimeDirectories.has(name)) {
        const canonical = realpathSync(path);
        if (!lstatSync(canonical).isDirectory() || !roots.some(parent => within(canonical, parent))) {
          throw new Error(`Pi runtime directory must remain inside a managed agent directory: ${path}`);
        }
        runtimePaths.add(canonical);
      } else if (name === "auth.json") {
        const entry = lstatSync(path);
        if (entry.isSymbolicLink()) {
          // Accepted targets: the credential store's auth.json, or (before migration) the configured
          // agent directory's own auth.json linked by Stow. The launcher grants the target; the
          // link itself stays host-owned.
          let target;
          try { target = realpathSync(path); } catch { target = undefined; }
          const store = storeDirectory(home);
          const storeAuth = store === undefined ? undefined : join(store, "auth.json");
          if (target !== storeAuth && !roots.some(other => other !== root && target === join(other, "auth.json"))) {
            throw new Error(`Pi auth state must be a regular file without hard links: ${path}`);
          }
          protectedPaths.add(path);
          continue;
        }
        // Refresh credentials in place, but do not grant a writable parent or a symlink-selected file.
        if (!entry.isFile() || entry.nlink !== 1) throw new Error(`Pi auth state must be a regular file without hard links: ${path}`);
        authFiles.add(path);
      } else {
        protect(path);
      }
    }
  }
  const controls = [...protectedPaths];
  for (const mutable of [...runtimePaths, ...authFiles]) {
    if (controls.some(path => within(path, mutable) || within(mutable, path))) {
      throw new Error(`Pi runtime state overlaps a protected control path: ${mutable}`);
    }
  }
  return { protectedPaths: controls, runtimePaths: [...runtimePaths], authFiles: [...authFiles] };
}

export function prepareAgentRuntime(agentDir: string): void {
  // Create only data directories before confinement; new code/config must be installed on the host.
  for (const name of runtimeDirectories) mkdirSync(join(agentDir, name), { recursive: true, mode: 0o700 });
}
