import { lstatSync } from "node:fs";
import { join } from "node:path";
import { assertCredentialGrants, canonicalCredentialPath } from "./credential-grants.mjs";

const tokenNames = [
  "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN",
  "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
];

export function prepareGithubEnvironment(inherited, loaded, home) {
  // The capture process inherits nono's environment. A real token in any alias would
  // remain readable if nono skipped the route, so never pass one to the supervisor.
  if (tokenNames.some((name) => inherited[name] || loaded[name])) {
    throw new Error("GitHub token environment variables cannot be passed to the Pi sandbox; use gh auth login for supervisor-side capture");
  }
  const environment = { ...loaded };
  for (const name of Object.keys(environment)) {
    if (tokenNames.includes(name) || name.startsWith("NONO_")) delete environment[name];
  }
  delete environment.GH_DEBUG;
  delete environment.DEBUG;
  // The project may set these via direnv; host-side gh must use the user's fixed store.
  environment.GH_CONFIG_DIR = join(home, ".config", "gh");
  delete environment.GH_HOST;
  delete environment.GITHUB_HOST;
  return environment;
}

export function direnvGithubEnvironment(environment) {
  const safe = { ...environment };
  for (const name of Object.keys(safe)) {
    if (tokenNames.includes(name) || name.startsWith("NONO_")) delete safe[name];
  }
  return safe;
}

export function assertGithubCredentialGrants(args, cwd, home, environment = {}, profile = {}) {
  const store = join(home, ".config", "gh");
  const protectedPaths = [canonicalCredentialPath(store, "GitHub")];
  const hosts = join(store, "hosts.yml");
  let entry;
  try {
    entry = lstatSync(hosts);
  } catch (error) {
    if (error.code !== "ENOENT") throw new Error("Cannot inspect GitHub credential store", { cause: error });
  }
  if (entry) {
    if (entry.isSymbolicLink()) protectedPaths.push(canonicalCredentialPath(hosts, "GitHub"));
    else if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error("GitHub credential file must be a regular file without hard links");
    }
  }
  assertCredentialGrants(args, cwd, home, environment, profile, protectedPaths, "GitHub");
}
