import { existsSync, lstatSync, mkdirSync, readdirSync, readlinkSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, sep } from "node:path";
import { canonicalCredentialPath } from "./credential-grants.mjs";

// These are data stores, not Pi resource-discovery or package-installation directories.
// pi-fff stores LMDB frecency/history beneath agent/fff when no editor database exists.
const runtimeDirectories = new Set(["sessions", "cache", "session-history", "tasks", "auth-profiles", "fff"]);
const requiredControls = ["settings.json", "extensions", "npm", "git", "lib", "mcp.json", "models.json", "trust.json"];
const within = (path, root) => root === sep || path === root || path.startsWith(`${root}${sep}`);

export function agentProtection(home, agentDir, environment = {}, profile = {}) {
  const roots = [...new Set([join(home, ".pi", "agent"), agentDir].filter(path => existsSync(path)).map(path => realpathSync(path)))];
  const canonicalHome = existsSync(home) ? realpathSync(home) : home;
  // These broad Linux default grants cannot be narrowed by splitting launcher arguments.
  const inheritedWrites = [join(home, ".cache"), ...(!within(canonicalHome, "/tmp") ? ["/tmp"] : [])];
  for (const field of ["allow", "write", "allow_file", "write_file"]) {
    for (const entry of profile.filesystem?.[field] ?? []) {
      if (typeof entry !== "string" && entry.when && entry.when !== "linux") continue;
      const template = typeof entry === "string" ? entry : entry.path;
      inheritedWrites.push(template.replace(/\$(?:\{(\w+)\}|(\w+))/g, (_, braced, bare) => {
        const name = braced || bare;
        const value = name === "HOME" ? home : environment[name];
        if (!value) throw new Error(`Missing Pi profile path variable: ${name}`);
        return value;
      }));
    }
  }
  const fixedWrites = inheritedWrites.map(path => canonicalCredentialPath(path, "Pi control"));
  const protectedPaths = new Set();
  const runtimePaths = new Set();
  const authFiles = new Set();
  const visited = new Set();
  let entries = 0;

  function canonicalPath(path) {
    if (!isAbsolute(path)) throw new Error(`Pi control path must be absolute: ${path}`);
    let parts = path.split(sep).filter(Boolean);
    let current = sep;
    let links = 0;
    while (parts.length) {
      const component = parts.shift();
      if (component === ".") continue;
      if (component === "..") { current = dirname(current); continue; }
      current = join(current, component);
      let entry;
      try { entry = lstatSync(current); }
      catch (error) {
        if (error.code !== "ENOENT") throw error;
        if (parts.includes("..")) throw new Error(`Unresolvable Pi control path: ${path}`);
        return join(current, ...parts);
      }
      if (entry.isSymbolicLink()) {
        // Include dangling Stow targets: future creation must not create an unprotected resource.
        protectedPaths.add(current);
        if (++links > 40) throw new Error(`Too many Pi control symlinks: ${path}`);
        const target = readlinkSync(current);
        parts = [...target.split(sep).filter(Boolean), ...parts];
        current = isAbsolute(target) ? sep : dirname(current);
      } else if (parts.length && !entry.isDirectory()) {
        throw new Error(`Not a Pi control directory: ${current}`);
      }
    }
    return current;
  }
  function protect(path) {
    protectedPaths.add(path);
    const canonical = canonicalPath(path);
    if (within(canonicalHome, canonical)) throw new Error(`Pi control path resolves to a home ancestor: ${path}`);
    if (fixedWrites.some(root => within(canonical, root) || within(root, canonical))) {
      throw new Error(`Pi control path overlaps a writable profile or default-group grant: ${path}`);
    }
    protectedPaths.add(canonical);
    scan(canonical);
  }

  function scan(path) {
    if (visited.has(path) || path.startsWith("/nix/store/")) return;
    visited.add(path);
    if (++entries > 100000) throw new Error("Pi control protection exceeds 100000 entries");
    let entry;
    try { entry = lstatSync(path); }
    catch (error) { if (error.code === "ENOENT") return; throw error; }
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

export function prepareAgentRuntime(agentDir) {
  // Create only data directories before confinement; new code/config must be installed on the host.
  for (const name of runtimeDirectories) mkdirSync(join(agentDir, name), { recursive: true, mode: 0o700 });
}
