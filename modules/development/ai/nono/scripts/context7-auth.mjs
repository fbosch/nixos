import { lstatSync } from "node:fs";
import { assertCredentialGrants, canonicalCredentialPath } from "./credential-grants.mjs";

export const context7SecretPath = "/run/secrets/context7-api-key";
const tokenNames = ["CONTEXT7_API_KEY"];

export function direnvContext7Environment(environment) {
  const safe = { ...environment };
  for (const name of tokenNames) delete safe[name];
  return safe;
}

export function prepareContext7Environment(inherited, loaded) {
  if (tokenNames.some((name) => inherited[name] || loaded[name])) {
    throw new Error("Context7 API key environment variables cannot be passed to the Pi sandbox; use the SOPS secret for supervisor-side capture");
  }
  return direnvContext7Environment(loaded);
}

export function assertContext7CredentialGrants(args, cwd, home, environment = {}, profile = {}, secretPath = context7SecretPath) {
  const protectedPath = canonicalCredentialPath(secretPath, "Context7");
  try {
    const entry = lstatSync(protectedPath);
    if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error("Context7 credential file must be a regular file without hard links");
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  assertCredentialGrants(args, cwd, home, environment, profile, [protectedPath], "Context7");
}
