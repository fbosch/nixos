import { existsSync, mkdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function existingDirectory(path) {
  if (!existsSync(path)) return undefined;
  const canonical = realpathSync(path);
  if (!statSync(canonical).isDirectory()) throw new Error(`Not a directory: ${path}`);
  return canonical;
}

function readJson(path, label) {
  if (!existsSync(path)) return undefined;
  try {
    return JSON.parse(readFileSync(path, "utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    throw new Error(`Cannot load ${label} from ${path}: ${error.message}`);
  }
}

function configuredReferences(settingsPath, base, home) {
  const settings = readJson(settingsPath, "project references");
  if (settings === undefined) return [];
  if (!record(settings)) throw new Error(`Project settings must contain a JSON object: ${settingsPath}`);
  if (settings.references === undefined) return [];
  if (!record(settings.references)) throw new Error(`Project references must contain an object: ${settingsPath}`);
  return Object.entries(settings.references).flatMap(([name, entry]) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error(`Invalid project reference name: ${name}`);
    if (!record(entry)) throw new Error(`Project reference "${name}" must contain an object.`);
    const path = typeof entry.path === "string" ? entry.path.trim() : "";
    const description = typeof entry.description === "string" ? entry.description.trim() : "";
    if (!path) throw new Error(`Project reference "${name}" requires a path.`);
    if (!description) throw new Error(`Project reference "${name}" requires a description.`);
    const expanded = path === "~" ? home : path.startsWith("~/") ? join(home, path.slice(2)) : path;
    const absolute = isAbsolute(expanded) ? expanded : resolve(base, expanded);
    if (!existsSync(absolute)) return [];
    const canonical = realpathSync(absolute);
    if (!statSync(canonical).isDirectory()) throw new Error(`Reference path is not a directory: ${path}`);
    return [{ name, path: canonical }];
  });
}

function docsCacheReferences(cwd) {
  const lock = readJson(join(cwd, "docs-lock.json"), "docs-cache references");
  if (lock === undefined) return [];
  if (!record(lock) || lock.version !== 1 || !record(lock.sources)) {
    throw new Error(`Invalid docs-cache lock file: ${join(cwd, "docs-lock.json")}`);
  }
  return Object.entries(lock.sources).map(([name, entry]) => {
    if (!name || name.length > 200 || /[<>:"/\\|?*\x00-\x1f\x7f]/.test(name) || /[.\s]$/u.test(name) ||
        [".", "..", "CON", "PRN", "AUX", "NUL", "COM1", "LPT1"].includes(name.toUpperCase())) {
      throw new Error(`Invalid docs-cache reference name: ${name}`);
    }
    if (!record(entry) || typeof entry.repo !== "string" || !entry.repo.trim()) {
      throw new Error(`Docs-cache source "${name}" requires a repository.`);
    }
    const path = resolve(cwd, ".docs", name);
    return { name, path: existsSync(path) ? realpathSync(path) : path };
  });
}

function projectTrusted(cwd, agentDir, home) {
  const project = join(cwd, ".pi");
  const localResources = ["settings.json", "mcp.json", "extensions", "skills", "prompts", "themes", "SYSTEM.md", "APPEND_SYSTEM.md"]
    .some((name) => existsSync(join(project, name)));
  const canonical = realpathSync(cwd);
  const ancestors = [];
  for (let path = canonical; ; path = dirname(path)) {
    ancestors.push(path);
    if (path === dirname(path)) break;
  }
  const userSkills = join(existingDirectory(home) ?? resolve(home), ".agents", "skills");
  if (!localResources && !ancestors.some((path) => {
    const skills = join(path, ".agents", "skills");
    return skills !== userSkills && existsSync(skills);
  })) return true;
  const decisions = readJson(join(agentDir, "trust.json"), "project trust");
  if (decisions === undefined) return false;
  if (!record(decisions) || Object.values(decisions).some((value) => value !== true && value !== false && value !== null)) {
    throw new Error(`Invalid project trust store: ${join(agentDir, "trust.json")}`);
  }
  // A saved ancestor decision applies to descendants; the nearest decision wins.
  for (const path of ancestors) {
    if (decisions[path] === true) return true;
    if (decisions[path] === false) return false;
  }
  return false;
}

function references(cwd, agentDir, home) {
  const trusted = projectTrusted(cwd, agentDir, home);
  const canonicalCwd = realpathSync(cwd);
  const global = configuredReferences(join(agentDir, "settings.json"), agentDir, home);
  const project = trusted ? configuredReferences(join(cwd, ".pi", "settings.json"), cwd, home) : [];
  const merged = new Map([...global, ...project].map((reference) => [reference.name.toLowerCase(), reference]));
  for (const [name, reference] of merged) {
    if (reference.path === canonicalCwd) merged.delete(name);
  }
  const docs = (trusted ? docsCacheReferences(cwd) : []).filter((reference) => reference.path !== canonicalCwd);
  for (const reference of docs) {
    if (merged.has(reference.name.toLowerCase())) {
      throw new Error(`Docs-cache reference "${reference.name}" conflicts with configured reference "${merged.get(reference.name.toLowerCase()).name}".`);
    }
  }
  return [...merged.values(), ...docs];
}

function existingFile(path) {
  return existsSync(path) && statSync(path).isFile();
}

export function launchArguments(cwd, agentDir, home, environment, profile, rawPi) {
  if (!isAbsolute(profile) || !existingFile(profile)) throw new Error(`Nix nono profile missing: ${profile}`);
  const grants = new Set();
  for (const reference of references(cwd, agentDir, home)) {
    const path = existingDirectory(reference.path);
    if (path !== undefined) grants.add(path);
  }
  // Stow links extension resources into the repo; only grant their actual targets.
  for (const path of [agentDir, join(home, ".agents", "skills"), join(home, ".cache", "pi")]) {
    const canonical = existingDirectory(path);
    if (canonical !== undefined) grants.add(canonical);
  }
  const configHome = environment.XDG_CONFIG_HOME || join(home, ".config");
  const dataHome = environment.XDG_DATA_HOME || join(home, ".local", "share");
  const cacheHome = environment.XDG_CACHE_HOME || join(home, ".cache");
  const extra = [];
  for (const path of [
    join(home, ".pi-lens"),
    environment.PI_HASHLINE_DIR || join(configHome, "pi-hashline-edit-pro"),
    environment.FFF_FRECENCY_DB || join(cacheHome, "nvim", "fff_nvim"),
    environment.FFF_HISTORY_DB || join(dataHome, "nvim", "fff_queries"),
  ]) {
    if (existingDirectory(path) !== undefined) extra.push("--allow", path);
  }
  for (const path of [join(configHome, "fbb", "data", "typos.abolish"), join(configHome, "nix", "git", "config")]) {
    if (existingFile(path)) extra.push("--read-file", path);
  }
  const direnvAllow = join(dataHome, "direnv", "allow");
  return [
    "run", "--profile", profile, "--allow-cwd", "--suppress-save-prompt", "/",
    ...extra,
    ...(existingDirectory(direnvAllow) !== undefined ? ["--read", direnvAllow] : []),
    ...[...grants].flatMap((path) => ["--allow", path]),
    "--", rawPi,
  ];
}

export function prepareJitiCache(temporaryDirectory = tmpdir(), platform = process.platform) {
  // Landlock grants bind existing paths; create the cache before nono resolves the profile.
  if (platform === "linux") mkdirSync(join(temporaryDirectory, "jiti"), { recursive: true, mode: 0o700 });
}

export function prepareNpmCache(home = homedir()) {
  // Like Jiti's cache, these narrow profile paths must exist before Landlock grants are built.
  for (const directory of ["_cacache", "_logs"]) {
    mkdirSync(join(home, ".npm", directory), { recursive: true, mode: 0o700 });
  }
}

export function launchCommand(args, cwd, agentDir, home, environment, nono, rawPi, profile) {
  if (!isAbsolute(rawPi) || !existsSync(rawPi)) throw new Error(`Raw Pi executable missing: ${rawPi}`);
  if (args[0] === "--no-sandbox") return [rawPi, ...args.slice(1)];
  if (!isAbsolute(nono) || !existsSync(nono)) throw new Error(`nono executable missing: ${nono}`);
  return [nono, ...launchArguments(cwd, agentDir, home, environment, profile, rawPi), ...args];
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [nono, rawPi, profile, ...args] = process.argv.slice(2);
    const environment = { ...process.env };
    // No mutable JS preload or module path may run in this pre-sandbox process.
    delete environment.NODE_OPTIONS;
    delete environment.NODE_PATH;
    if (process.platform === "darwin" && !environment.XDG_RUNTIME_DIR) {
      environment.XDG_RUNTIME_DIR = environment.TMPDIR || tmpdir();
    }
    const agentDir = environment.PI_CODING_AGENT_DIR || join(homedir(), ".pi", "agent");
    const command = launchCommand(args, process.cwd(), agentDir, homedir(), environment, nono, rawPi, profile);
    if (command[0] === nono) {
      prepareJitiCache();
      prepareNpmCache();
    }
    const child = spawnSync(command[0], command.slice(1), { stdio: "inherit", env: environment });
    if (child.error) throw child.error;
    if (child.signal) process.kill(process.pid, child.signal);
    process.exit(child.status ?? 1);
  } catch (error) {
    console.error(`pi sandbox launch: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
}
