import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, readlinkSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, join, sep } from "node:path";

function optionalStat(path) {
  try {
    return lstatSync(path);
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    throw error;
  }
}

function seatbeltString(path) {
  if (/[\x00-\x1f\x7f]/u.test(path)) throw new Error(`Unsupported control character in startup path: ${JSON.stringify(path)}`);
  return JSON.stringify(path);
}

function within(path, root) {
  return path === root || path.startsWith(`${root}${sep}`) || root === sep;
}

function startupPaths(home, environment) {
  const configs = new Set([join(home, ".config"), environment.XDG_CONFIG_HOME].filter(Boolean));
  const caches = new Set([join(home, ".cache"), environment.XDG_CACHE_HOME].filter(Boolean));
  const data = new Set([join(home, ".local", "share"), environment.XDG_DATA_HOME].filter(Boolean));
  for (const path of [...configs, ...caches, ...data]) {
    if (!isAbsolute(path)) throw new Error(`Startup directory must be absolute: ${path}`);
    if (path.split(sep).includes("..")) throw new Error(`Startup directory contains parent traversal: ${path}`);
  }
  return [
    join(home, ".shinit"),
    join(home, "dotfiles", ".shinit"),
    join(home, "dotfiles", ".config", "fish"),
    join(home, ".inshellisense", "key-bindings.fish"),
    ...[...configs].flatMap((path) => [join(path, "fish"), join(path, "starship.toml"), join(path, "starship-tty.toml")]),
    ...[...caches].map((path) => join(path, "fish")),
    ...[...data].flatMap((path) => ["vendor_conf.d", "vendor_functions.d", "vendor_completions.d"].map((name) => join(path, "fish", name))),
  ];
}

export function shellProtection(home, environment = {}) {
  if (!isAbsolute(home)) throw new Error(`Home directory must be absolute: ${home}`);
  if (home.split(sep).includes("..")) throw new Error(`Home directory contains parent traversal: ${home}`);
  const canonicalHome = realpathSync.native(home);
  const roots = new Set();
  const ancestors = new Set();
  const reads = new Set();
  const visited = new Set();
  let entries = 0;

  function guardAncestors(path) {
    for (let parent = dirname(path); ; parent = dirname(parent)) {
      ancestors.add(parent);
      if (parent === dirname(parent)) break;
    }
  }

  function canonicalPath(path) {
    let parts = path.split(sep).filter(Boolean);
    let current = sep;
    let links = 0;
    while (parts.length) {
      const component = parts.shift();
      if (component === ".") continue;
      if (component === "..") {
        ancestors.add(current);
        guardAncestors(current);
        current = dirname(current);
        continue;
      }
      current = join(current, component);
      const stat = optionalStat(current);
      if (stat?.isSymbolicLink()) {
        // Preserve filesystem traversal order: normalize("link/../file") can select the wrong target.
        ancestors.add(current);
        guardAncestors(current);
        if (++links > 40) throw new Error(`Too many startup symlinks: ${path}`);
        const target = readlinkSync(current);
        parts = [...target.split(sep).filter(Boolean), ...parts];
        current = isAbsolute(target) ? sep : dirname(current);
      } else if (!stat) {
        if (parts.includes("..")) throw new Error(`Unresolvable startup parent traversal: ${path}`);
        current = join(current, ...parts);
        break;
      } else if (parts.length && !stat.isDirectory()) {
        throw new Error(`Not a startup directory: ${current}`);
      }
    }
    guardAncestors(current);
    return current;
  }

  function protect(path, scan = true) {
    seatbeltString(path);
    roots.add(path);
    guardAncestors(path);
    const canonical = canonicalPath(path);
    seatbeltString(canonical);
    if (within(canonicalHome, canonical)) throw new Error(`Startup path resolves to a home ancestor: ${path}`);
    roots.add(canonical);
    const stat = optionalStat(canonical);
    if (!stat || !scan || visited.has(canonical)) return;
    visited.add(canonical);
    if (++entries > 10000) throw new Error("Startup protection exceeds 10000 entries; review the linked configuration tree.");
    reads.add(canonical);
    if (stat.isDirectory()) {
      for (const name of readdirSync(canonical).sort()) {
        const child = join(canonical, name);
        const childStat = lstatSync(child);
        if (childStat.isSymbolicLink() || childStat.isDirectory()) protect(child);
        else checkFile(child, childStat);
      }
    } else {
      checkFile(canonical, stat);
    }
  }

  function checkFile(path, stat) {
    if (!stat.isFile()) throw new Error(`Unsupported startup file type: ${path}`);
    // Existing hard-link aliases cannot be enumerated safely. Immutable Nix store files are exempt.
    const immutableStoreFile = path.startsWith("/nix/store/") && stat.uid === 0 && (stat.mode & 0o222) === 0;
    if (stat.nlink > 1 && !immutableStoreFile) throw new Error(`Hard-linked startup file is not supported: ${path}`);
  }

  for (const path of startupPaths(home, environment)) protect(path);
  const profileDirectory = join(canonicalHome, ".local", "state", "nono", "pi-profiles");
  // This is authority-bearing launch state, not a writable cache. Every session protects it.
  protect(profileDirectory, false);
  const covered = (path) => [...roots].some((root) => within(path, root));
  const minimalRoots = [...roots].filter((path) => ![...roots].some((other) => other !== path && within(path, other))).sort();
  const filters = [
    ...minimalRoots.map((path) => `(subpath ${seatbeltString(path)})`),
    ...[...ancestors].filter((path) => !covered(path)).sort().map((path) => `(literal ${seatbeltString(path)})`),
  ];
  return {
    profileDirectory,
    readPaths: [...reads].filter((path) => ![...reads].some((other) => other !== path && within(path, other))).sort(),
    rules: [`(deny file-write* ${filters.join(" ")})`],
  };
}

function privateProfileDirectory(home) {
  let path = realpathSync.native(home);
  for (const component of [".local", "state", "nono", "pi-profiles"]) {
    path = join(path, component);
    try {
      mkdirSync(path, { mode: 0o700 });
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
    }
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid() || (stat.mode & 0o022) !== 0) {
      throw new Error(`Unsafe Pi profile directory: ${path}`);
    }
  }
  return path;
}

export function withProtectedShellProfile(profilePath, home, environment, run, platform = process.platform) {
  // Linux needs a different boundary: Landlock cannot subtract writes from an ancestor grant.
  if (platform !== "darwin") return run(profilePath);
  let profile;
  try {
    profile = JSON.parse(readFileSync(profilePath, "utf8"));
  } catch (error) {
    throw new Error(`Cannot read Pi nono profile ${profilePath}: ${error.message}`, { cause: error });
  }
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) throw new Error("Invalid Pi nono profile.");
  if (profile.filesystem !== undefined && (!profile.filesystem || typeof profile.filesystem !== "object" || Array.isArray(profile.filesystem))) {
    throw new Error("Invalid Pi nono filesystem profile.");
  }
  const reads = profile.filesystem?.read === undefined ? [] : profile.filesystem.read;
  const rules = profile.unsafe_macos_seatbelt_rules === undefined ? [] : profile.unsafe_macos_seatbelt_rules;
  if (!Array.isArray(reads) || !Array.isArray(rules) || !rules.every((rule) => typeof rule === "string")) {
    throw new Error("Invalid Pi nono profile rule lists.");
  }
  const directory = privateProfileDirectory(home);
  const protection = shellProtection(home, environment);
  if (directory !== protection.profileDirectory) throw new Error("Pi profile directory changed during startup.");
  const session = mkdtempSync(join(directory, "session-"));
  try {
    const effectivePath = join(session, "profile.json");
    writeFileSync(effectivePath, JSON.stringify({
      ...profile,
      filesystem: { ...profile.filesystem, read: [...reads, ...protection.readPaths] },
      unsafe_macos_seatbelt_rules: [...rules, ...protection.rules],
    }), { flag: "wx", mode: 0o600 });
    return run(effectivePath);
  } finally {
    rmSync(session, { recursive: true, force: true });
  }
}
