import { existsSync, lstatSync, realpathSync, statSync, type Stats } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { existingDirectory, expandTilde, isRecord, readJsonFile } from "../shared/paths.mts";
import type { ErrnoError } from "../shared/types.mts";

export interface Reference {
  name: string;
  path: string;
}

// Project references: settings and docs-cache entries that may receive sandbox grants.

function configuredReferences(settingsPath: string, base: string, home: string): Reference[] {
  const settings = readJsonFile(settingsPath, "project references");
  if (settings === undefined) return [];
  if (!isRecord(settings)) throw new Error(`Project settings must contain a JSON object: ${settingsPath}`);
  if (settings.references === undefined) return [];
  if (!isRecord(settings.references)) throw new Error(`Project references must contain an object: ${settingsPath}`);
  return Object.entries(settings.references).flatMap(([name, entry]) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error(`Invalid project reference name: ${name}`);
    if (!isRecord(entry)) throw new Error(`Project reference "${name}" must contain an object.`);
    const path = typeof entry.path === "string" ? entry.path.trim() : "";
    const description = typeof entry.description === "string" ? entry.description.trim() : "";
    if (!path) throw new Error(`Project reference "${name}" requires a path.`);
    if (!description) throw new Error(`Project reference "${name}" requires a description.`);
    const expanded = expandTilde(path, home);
    const absolute = isAbsolute(expanded) ? expanded : resolve(base, expanded);
    if (!existsSync(absolute)) return [];
    const canonical = realpathSync(absolute);
    if (!statSync(canonical).isDirectory()) throw new Error(`Reference path is not a directory: ${path}`);
    return [{ name, path: canonical }];
  });
}

function docsCacheReferences(cwd: string): Reference[] {
  const lock = readJsonFile(join(cwd, "docs-lock.json"), "docs-cache references");
  if (lock === undefined) return [];
  if (!isRecord(lock) || lock.version !== 1 || !isRecord(lock.sources)) {
    throw new Error(`Invalid docs-cache lock file: ${join(cwd, "docs-lock.json")}`);
  }
  return Object.entries(lock.sources).map(([name, entry]) => {
    if (!name || name.length > 200 || /[<>:"/\\|?*\x00-\x1f\x7f]/.test(name) || /[.\s]$/u.test(name) ||
        [".", "..", "CON", "PRN", "AUX", "NUL", "COM1", "LPT1"].includes(name.toUpperCase())) {
      throw new Error(`Invalid docs-cache reference name: ${name}`);
    }
    if (!isRecord(entry) || typeof entry.repo !== "string" || !entry.repo.trim()) {
      throw new Error(`Docs-cache source "${name}" requires a repository.`);
    }
    const path = resolve(cwd, ".docs", name);
    return { name, path: existsSync(path) ? realpathSync(path) : path };
  });
}

function projectTrusted(cwd: string, agentDir: string, home: string): boolean {
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
  const decisions = readJsonFile(join(agentDir, "trust.json"), "project trust");
  if (decisions === undefined) return false;
  if (!isRecord(decisions) || Object.values(decisions).some((value) => value !== true && value !== false && value !== null)) {
    throw new Error(`Invalid project trust store: ${join(agentDir, "trust.json")}`);
  }
  // A saved ancestor decision applies to descendants; the nearest decision wins.
  for (const path of ancestors) {
    if (decisions[path] === true) return true;
    if (decisions[path] === false) return false;
  }
  return false;
}

export function references(cwd: string, agentDir: string, home: string): Reference[] {
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
      throw new Error(`Docs-cache reference "${reference.name}" conflicts with configured reference "${merged.get(reference.name.toLowerCase())!.name}".`);
    }
  }
  return [...merged.values(), ...docs];
}

// Reference settings are sandbox-writable, so grants beyond cwd and the paired repositories need a host-only approval.
export function referenceApprovalStore(home: string): string {
  return join(existingDirectory(home) ?? resolve(home), ".local", "state", "pi-sandbox", "approved-references.json");
}

export function approvedReferenceRoots(home: string): string[] {
  const store = referenceApprovalStore(home);
  let entry: Stats;
  try {
    entry = lstatSync(store);
  } catch (error) {
    if ((error as ErrnoError).code === "ENOENT") return [];
    throw error;
  }
  if (!entry.isFile() || entry.uid !== process.getuid!() || (entry.mode & 0o022) !== 0) {
    throw new Error(`Reference approvals must be a user-owned regular file without group or world write access: ${store}`);
  }
  const approvals = readJsonFile(store, "reference approvals");
  if (!Array.isArray(approvals) || !approvals.every((path) => typeof path === "string" && isAbsolute(path))) {
    throw new Error(`Reference approvals must be a JSON array of absolute paths: ${store}`);
  }
  return (approvals as string[]).flatMap((path) => existsSync(path) ? [realpathSync(path)] : []);
}
