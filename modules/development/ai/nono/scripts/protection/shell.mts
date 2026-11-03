import * as Effect from "effect/Effect";
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync, type Stats } from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";
import { optionalLstat, within } from "../shared/paths.mts";
import type { Environment, ErrnoError, NonoProfile } from "../shared/types.mts";
import { resolveComponents } from "./resolve.mts";
import { InvalidConfigError, type SandboxError, UnsafeFileError, attempt } from "../shared/errors.mts";

function seatbeltString(path: string): string {
  if (/[\x00-\x1f\x7f]/u.test(path)) throw new UnsafeFileError({ message: `Unsupported control character in startup path: ${JSON.stringify(path)}` });
  return JSON.stringify(path);
}

function startupPaths(home: string, environment: Environment): string[] {
  const configs = new Set([join(home, ".config"), environment.XDG_CONFIG_HOME].filter(Boolean) as string[]);
  const caches = new Set([join(home, ".cache"), environment.XDG_CACHE_HOME].filter(Boolean) as string[]);
  const data = new Set([join(home, ".local", "share"), environment.XDG_DATA_HOME].filter(Boolean) as string[]);
  for (const path of [...configs, ...caches, ...data]) {
    if (!isAbsolute(path)) throw new InvalidConfigError({ message: `Startup directory must be absolute: ${path}` });
    if (path.split(sep).includes("..")) throw new InvalidConfigError({ message: `Startup directory contains parent traversal: ${path}` });
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

/** Shell startup paths to keep read-only, as Seatbelt rules (macOS) and paths (Linux). */
export interface ShellProtection {
  profileDirectory: string;
  protectedPaths: string[];
  readPaths: string[];
  rules: string[];
}

function shellProtectionSync(home: string, environment: Environment = {}, additionalPaths: readonly string[] = []): ShellProtection {
  if (!isAbsolute(home)) throw new InvalidConfigError({ message: `Home directory must be absolute: ${home}` });
  if (home.split(sep).includes("..")) throw new InvalidConfigError({ message: `Home directory contains parent traversal: ${home}` });
  const canonicalHome = realpathSync.native(home);
  const roots = new Set<string>();
  const ancestors = new Set<string>();
  const reads = new Set<string>();
  const visited = new Set<string>();
  let entries = 0;

  function guardAncestors(path: string): void {
    for (let parent = dirname(path); ; parent = dirname(parent)) {
      ancestors.add(parent);
      if (parent === dirname(parent)) break;
    }
  }

  function canonicalPath(path: string): string {
    const guard = (entry: string) => {
      ancestors.add(entry);
      guardAncestors(entry);
    };
    const canonical = resolveComponents(path, "startup", { onLink: guard, onParent: guard });
    guardAncestors(canonical);
    return canonical;
  }

  function protect(path: string, scan = true): void {
    seatbeltString(path);
    roots.add(path);
    guardAncestors(path);
    const canonical = canonicalPath(path);
    seatbeltString(canonical);
    if (within(canonicalHome, canonical)) throw new UnsafeFileError({ message: `Startup path resolves to a home ancestor: ${path}` });
    roots.add(canonical);
    const stat = optionalLstat(canonical);
    if (!stat || !scan || visited.has(canonical)) return;
    visited.add(canonical);
    if (++entries > 10000) throw new UnsafeFileError({ message: "Startup protection exceeds 10000 entries; review the linked configuration tree." });
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

  function checkFile(path: string, stat: Stats): void {
    if (!stat.isFile()) throw new UnsafeFileError({ message: `Unsupported startup file type: ${path}` });
    // Existing hard-link aliases cannot be enumerated safely. Immutable Nix store files are exempt.
    const immutableStoreFile = path.startsWith("/nix/store/") && stat.uid === 0 && (stat.mode & 0o222) === 0;
    if (stat.nlink > 1 && !immutableStoreFile) throw new UnsafeFileError({ message: `Hard-linked startup file is not supported: ${path}` });
  }

  for (const path of startupPaths(home, environment)) protect(path);
  // Agent controls are already recursively checked by the launch plan; retain their alias and ancestor denials.
  for (const path of additionalPaths) protect(path, false);
  const profileDirectory = join(canonicalHome, ".local", "state", "nono", "pi-profiles");
  // This is authority-bearing launch state, not a writable cache. Every session protects it.
  protect(profileDirectory, false);
  const covered = (path: string) => [...roots].some((root) => within(path, root));
  const minimalRoots = [...roots].filter((path) => ![...roots].some((other) => other !== path && within(path, other))).sort();
  const filters = [
    ...minimalRoots.map((path) => `(subpath ${seatbeltString(path)})`),
    ...[...ancestors].filter((path) => !covered(path)).sort().map((path) => `(literal ${seatbeltString(path)})`),
  ];
  return {
    profileDirectory,
    protectedPaths: minimalRoots,
    readPaths: [...reads].filter((path) => ![...reads].some((other) => other !== path && within(path, other))).sort(),
    rules: [`(deny file-write* ${filters.join(" ")})`],
  };
}

/** Shell startup paths to keep read-only, with their Seatbelt rules. */
export function shellProtection(home: string, environment: Environment = {}, additionalPaths: readonly string[] = []): Effect.Effect<ShellProtection, SandboxError> {
  return attempt(() => shellProtectionSync(home, environment, additionalPaths));
}

function privateProfileDirectory(home: string): string {
  let path = realpathSync.native(home);
  for (const component of [".local", "state", "nono", "pi-profiles"]) {
    path = join(path, component);
    try {
      mkdirSync(path, { mode: 0o700 });
    } catch (error) {
      if ((error as ErrnoError).code !== "EEXIST") throw error;
    }
    const stat = lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink() || stat.uid !== process.getuid!() || (stat.mode & 0o022) !== 0) {
      throw new UnsafeFileError({ message: `Unsafe Pi profile directory: ${path}` });
    }
  }
  return path;
}

/** A Seatbelt regex that matches `path` and anything that starts with it. */
function seatbeltPrefix(path: string, { childrenOnly = false }: { childrenOnly?: boolean } = {}): string {
  seatbeltString(path);
  if (path.includes('"')) throw new UnsafeFileError({ message: `Unsupported quote in credential path: ${path}` });
  const escaped = path.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
  return `(regex #"^${escaped}${childrenOnly ? "/" : ""}")`;
}

/**
 * Seatbelt denial for credential stores in executor mode: auth.json and its lock files, and the
 * files inside credential directories (auth-profiles/, the credential store). Directories stay
 * listable so profile names remain known.
 */
export function credentialDenyRule(credentialPaths: readonly string[]): string | undefined {
  if (credentialPaths.length === 0) return undefined;
  const directory = (path: string) => {
    try { return statSync(path).isDirectory(); } catch { return basename(path) === "auth-profiles"; }
  };
  const filters = credentialPaths.map((path) => seatbeltPrefix(path, { childrenOnly: directory(path) }));
  return `(deny file-read* file-write* ${filters.join(" ")})`;
}

export function withProtectedShellProfile<T>(profilePath: string, home: string, environment: Environment, run: (profilePath: string) => T, platform: NodeJS.Platform = process.platform, additionalPaths: readonly string[] = [], credentialPaths: readonly string[] = []): T {
  // Linux needs a different boundary: Landlock cannot subtract writes from an ancestor grant.
  if (platform !== "darwin") return run(profilePath);
  let profile: NonoProfile;
  try {
    profile = JSON.parse(readFileSync(profilePath, "utf8"));
  } catch (error) {
    throw new InvalidConfigError({ message: `Cannot read Pi nono profile ${profilePath}: ${(error as Error).message}`, cause: error });
  }
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) throw new InvalidConfigError({ message: "Invalid Pi nono profile." });
  if (profile.filesystem !== undefined && (!profile.filesystem || typeof profile.filesystem !== "object" || Array.isArray(profile.filesystem))) {
    throw new InvalidConfigError({ message: "Invalid Pi nono filesystem profile." });
  }
  const reads = profile.filesystem?.read === undefined ? [] : profile.filesystem.read;
  const rules = profile.unsafe_macos_seatbelt_rules === undefined ? [] : profile.unsafe_macos_seatbelt_rules;
  if (!Array.isArray(reads) || !Array.isArray(rules) || !rules.every((rule) => typeof rule === "string")) {
    throw new InvalidConfigError({ message: "Invalid Pi nono profile rule lists." });
  }
  const directory = privateProfileDirectory(home);
  const protection = shellProtectionSync(home, environment, additionalPaths);
  if (directory !== protection.profileDirectory) throw new UnsafeFileError({ message: "Pi profile directory changed during startup." });
  const session = mkdtempSync(join(directory, "session-"));
  try {
    const effectivePath = join(session, "profile.json");
    writeFileSync(effectivePath, JSON.stringify({
      ...profile,
      filesystem: { ...profile.filesystem, read: [...reads, ...protection.readPaths] },
      unsafe_macos_seatbelt_rules: [...rules, ...protection.rules, ...[credentialDenyRule(credentialPaths)].filter(Boolean)],
    }), { flag: "wx", mode: 0o600 });
    return run(effectivePath);
  } finally {
    rmSync(session, { recursive: true, force: true });
  }
}
