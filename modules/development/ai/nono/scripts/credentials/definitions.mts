import * as Effect from "effect/Effect";
import { lstatSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { isRecord, readJsonFile } from "../shared/paths.mts";
import type { Environment, ErrnoError, NonoProfile } from "../shared/types.mts";
import { assertCredentialGrants, canonicalCredentialPath } from "./grants.mts";
import { InvalidConfigError, UnsafeFileError, attempt, type SandboxError } from "../shared/errors.mts";
import type { GrantPlan } from "../shared/grant-plan.mts";

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
  if (!isRecord(definitions)) throw new InvalidConfigError({ message: `Credential declarations must be a JSON object: ${path}` });
  // SAFETY: entries() validates each declaration's name, route variable, source type and aliases
  // before any caller reads a field; the remaining fields are read as declared in credentials.json.
  return definitions as unknown as CredentialDefinitions;
}

export const credentialDefinitions: CredentialDefinitions = loadDefinitions();

function entries(definitions: CredentialDefinitions): [string, CredentialDefinition][] {
  for (const [name, definition] of Object.entries(definitions)) {
    if (!/^[A-Za-z0-9_]+$/.test(name) || typeof definition.route?.env_var !== "string" || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(definition.route.env_var)) {
      throw new InvalidConfigError({ message: `Invalid credential declaration: ${name}` });
    }
    if (!["file", "command"].includes(definition.source?.type)) throw new InvalidConfigError({ message: `Invalid credential source: ${name}` });
    for (const alias of definition.aliases ?? []) {
      if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(alias)) throw new InvalidConfigError({ message: `Invalid credential environment alias: ${name}` });
    }
  }
  return Object.entries(definitions);
}

function tokenNames(definitions: CredentialDefinitions): string[] {
  return entries(definitions).flatMap(([, definition]) => [definition.route.env_var, ...(definition.aliases ?? [])]);
}

function expandHome(value: string, home: string): string {
  return value.replace(/\$(?:\{([^}]+)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_, braced: string | undefined, bare: string | undefined) => {
    if ((braced || bare) !== "HOME") throw new InvalidConfigError({ message: "Credential paths may only reference HOME" });
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
      throw new InvalidConfigError({ message: `${definition.label ?? name} credential environment variables cannot be passed to Pi; use supervisor-side capture` });
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
      throw new UnsafeFileError({ message: `${label} credential file must be a regular file without hard links` });
    }
  } catch (error) {
    if ((error as ErrnoError).code !== "ENOENT") throw error;
  }
  return canonical;
}

/** Fail when a grant reaches any credential source or protected path that a declaration names. */
export function assertCredentialSourceGrants(plan: GrantPlan, cwd: string, home: string, environment: Environment = {}, profile: NonoProfile = {}, definitions: CredentialDefinitions = credentialDefinitions): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    for (const [name, definition] of yield* attempt(() => entries(definitions))) {
      const label = definition.label ?? name;
      const source = definition.source;
      const protectedPaths = yield* attempt(() => [
        ...(source.protected_directories ?? []).map((path) => canonicalCredentialPath(expandHome(path, home), label)),
        ...[...(source.protected_files ?? []), ...(source.type === "file" ? [source.path!] : [])].map((path) => protectedFile(expandHome(path, home), label)),
      ]);
      yield* assertCredentialGrants(plan, cwd, home, environment, profile, protectedPaths, label);
    }
  });
}
