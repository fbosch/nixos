import { lstatSync, readFileSync } from "node:fs";
import { assertCredentialGrants, canonicalCredentialPath } from "./credential-grants.mjs";

export const credentialDefinitions = JSON.parse(readFileSync(new URL("./credentials.json", import.meta.url), "utf8"));

function entries(definitions) {
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

function tokenNames(definitions) {
  return entries(definitions).flatMap(([, definition]) => [definition.route.env_var, ...(definition.aliases ?? [])]);
}

function expandHome(value, home) {
  return value.replace(/\$(?:\{([^}]+)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_, braced, bare) => {
    if ((braced || bare) !== "HOME") throw new Error("Credential paths may only reference HOME");
    return home;
  });
}

export function credentialEnvironmentForDirenv(environment, definitions = credentialDefinitions) {
  const safe = { ...environment };
  const names = new Set(tokenNames(definitions));
  for (const name of Object.keys(safe)) {
    if (names.has(name) || name.startsWith("NONO_")) delete safe[name];
  }
  return safe;
}

export function prepareCredentialEnvironment(inherited, loaded, home, definitions = credentialDefinitions) {
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

function protectedFile(path, label) {
  const canonical = canonicalCredentialPath(path, label);
  try {
    const entry = lstatSync(canonical);
    if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error(`${label} credential file must be a regular file without hard links`);
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  return canonical;
}

export function assertCredentialSourceGrants(args, cwd, home, environment = {}, profile = {}, definitions = credentialDefinitions) {
  for (const [name, definition] of entries(definitions)) {
    const label = definition.label ?? name;
    const source = definition.source;
    const directories = (source.protected_directories ?? []).map((path) => canonicalCredentialPath(expandHome(path, home), label));
    const files = [...(source.protected_files ?? []), ...(source.type === "file" ? [source.path] : [])]
      .map((path) => protectedFile(expandHome(path, home), label));
    assertCredentialGrants(args, cwd, home, environment, profile, [...directories, ...files], label);
  }
}
