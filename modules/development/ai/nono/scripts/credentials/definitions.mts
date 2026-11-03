import { lstatSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { isRecord, readJsonFile } from "../shared/paths.mts";
import type { Environment, ErrnoError, NonoProfile } from "../shared/types.mts";
import { assertCredentialGrants, canonicalCredentialPath } from "./grants.mts";

/** One entry of `credentials.json`. Nix reads the same file to build nono's credential routes. */
export interface CredentialDefinition {
  label?: string;
  route: { upstream: string; env_var: string; inject_header?: string; credential_format?: string };
  source: {
    type: "file" | "command";
    path?: string;
    package?: string;
    program?: string;
    script?: string;
    args?: string[];
    protected_directories?: string[];
    protected_files?: string[];
    sops?: { file: string; key: string };
  };
  aliases?: string[];
  environment?: { unset?: string[]; set?: Record<string, string> };
  capture?: { timeout_secs?: number; cache_ttl_secs?: number };
}

export type CredentialDefinitions = Record<string, CredentialDefinition>;

function loadDefinitions(): CredentialDefinitions {
  const path = fileURLToPath(new URL("./credentials.json", import.meta.url));
  // Packaged beside this module in the Nix store; an unreadable declaration must stop the launcher.
  const definitions = readJsonFile(path, "credential declarations");
  if (!isRecord(definitions)) throw new Error(`Credential declarations must be a JSON object: ${path}`);
  // SAFETY: entries() validates each declaration's name, route variable, source type and aliases
  // before any caller reads a field; the remaining fields are read as declared in credentials.json.
  return definitions as unknown as CredentialDefinitions;
}

export const credentialDefinitions: CredentialDefinitions = loadDefinitions();

function entries(definitions: CredentialDefinitions): [string, CredentialDefinition][] {
  for (const [name, definition] of Object.entries(definitions)) {
    if (!/^[A-Za-z0-9_]+$/.test(name) || typeof definition.route?.env_var !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(definition.route.env_var)) {
      throw new Error(`Invalid credential declaration: ${name}`);
    }
    if (!["file", "command"].includes(definition.source?.type)) throw new Error(`Invalid credential source: ${name}`);
    for (const alias of definition.aliases ?? []) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(alias)) throw new Error(`Invalid credential environment alias: ${name}`);
    }
  }
  return Object.entries(definitions);
}

function tokenNames(definitions: CredentialDefinitions): string[] {
  return entries(definitions).flatMap(([, definition]) => [definition.route.env_var, ...(definition.aliases ?? [])]);
}

function expandHome(value: string, home: string): string {
  return value.replace(/\$(?:\{([^}]+)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_, braced: string | undefined, bare: string | undefined) => {
    if ((braced || bare) !== "HOME") throw new Error("Credential paths may only reference HOME");
    return home;
  });
}

export function credentialEnvironmentForDirenv(environment: Environment, definitions: CredentialDefinitions = credentialDefinitions): Environment {
  const safe = { ...environment };
  const names = new Set(tokenNames(definitions));
  for (const name of Object.keys(safe)) {
    if (names.has(name) || name.startsWith("NONO_")) delete safe[name];
  }
  return safe;
}

export function prepareCredentialEnvironment(inherited: Environment, loaded: Environment, home: string, definitions: CredentialDefinitions = credentialDefinitions): Environment {
  for (const [name, definition] of entries(definitions)) {
    const aliases = [definition.route.env_var, ...(definition.aliases ?? [])];
    // Even a skipped capture route must never leave a real credential in the child environment.
    if (aliases.some((alias) => inherited[alias] || loaded[alias])) {
      throw new Error(`${definition.label ?? name} credential environment variables cannot be passed to Pi; use supervisor-side capture`);
    }
  }
  const environment = credentialEnvironmentForDirenv(loaded, definitions);
  for (const [, definition] of entries(definitions)) {
    for (const name of definition.environment?.unset ?? []) delete environment[name];
    for (const [name, value] of Object.entries(definition.environment?.set ?? {})) {
      environment[name] = expandHome(value, home);
    }
  }
  return environment;
}

function protectedFile(path: string, label: string): string {
  const canonical = canonicalCredentialPath(path, label);
  try {
    const entry = lstatSync(canonical);
    if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error(`${label} credential file must be a regular file without hard links`);
    }
  } catch (error) {
    if ((error as ErrnoError).code !== "ENOENT") throw error;
  }
  return canonical;
}

export function assertCredentialSourceGrants(args: readonly string[], cwd: string, home: string, environment: Environment = {}, profile: NonoProfile = {}, definitions: CredentialDefinitions = credentialDefinitions): void {
  for (const [name, definition] of entries(definitions)) {
    const label = definition.label ?? name;
    const source = definition.source;
    const directories = (source.protected_directories ?? []).map((path) => canonicalCredentialPath(expandHome(path, home), label));
    const files = [...(source.protected_files ?? []), ...(source.type === "file" ? [source.path!] : [])]
      .map((path) => protectedFile(expandHome(path, home), label));
    assertCredentialGrants(args, cwd, home, environment, profile, [...directories, ...files], label);
  }
}
