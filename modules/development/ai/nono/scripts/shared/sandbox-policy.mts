import { Ajv, type AnySchemaObject } from "ajv";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { InvalidConfigError } from "./errors.mts";
import type { Environment } from "./types.mts";

// Filesystem, SSH and exception policy of the `pi.sandbox` Nix option. Nix serializes it into
// the store and the wrapper pins that file in PI_SANDBOX_POLICY; this module reads it once, at
// load time, before any project environment exists. Types mirror sandbox-policy.schema.json.

type Base = "home" | "config" | "cache" | "data";

export interface Grant {
  base: Base;
  path: string;
  override?: string;
  type: "directory" | "file";
  access: "read" | "readwrite";
}

export interface SandboxPolicy {
  version: 1;
  filesystem: {
    grants: Record<string, Grant>;
    agent: { writableHomePaths: string[]; runtimeEntries: string[]; controlEntries: string[] };
    shellStartup: Record<Base, string[]>;
    runtimeDirectory: { secrets: string[]; services: string[] };
  };
  ssh: { publicFiles: string[]; defaultIdentity: string };
  exceptions: { configurationRepositories: string[] };
}

function readJson(path: string | URL, label: string): AnySchemaObject {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (cause) {
    throw new InvalidConfigError({ message: `Cannot read ${label}: ${path}`, cause });
  }
}

const validate = new Ajv({ strict: true, allErrors: false }).compile(readJson(new URL("./sandbox-policy.schema.json", import.meta.url), "sandbox policy schema"));

function deepFreeze<T>(value: T): T {
  if (value && typeof value === "object") {
    for (const child of Object.values(value)) deepFreeze(child);
    Object.freeze(value);
  }
  return value;
}

/** Load and validate a sandbox policy; fails closed on any schema violation. */
export function loadSandboxPolicy(path: string | URL = new URL("./sandbox-policy.json", import.meta.url)): SandboxPolicy {
  const value = readJson(path, "sandbox policy");
  if (!validate(value)) throw new InvalidConfigError({ message: `Invalid sandbox policy ${path}: ${validate.errors?.map((error) => `${error.instancePath || "/"} ${error.message}`).join("; ")}` });
  // SAFETY: the schema accepted the value, and SandboxPolicy mirrors that schema.
  return deepFreeze(value) as unknown as SandboxPolicy;
}

export const sandboxPolicy: SandboxPolicy = loadSandboxPolicy(process.env.PI_SANDBOX_POLICY || undefined);

/** Grants in name order: the order of their nono arguments, which carries no meaning. */
export const grants: readonly (Grant & { name: string })[] = Object.entries(sandboxPolicy.filesystem.grants)
  .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0))
  .map(([name, grant]) => ({ name, ...grant }));

/** `config`, `cache` and `data` from the given environment, or their $HOME defaults. */
export function baseDirectory(base: Base, home: string, environment: Environment): string {
  if (base === "home") return home;
  if (base === "config") return environment.XDG_CONFIG_HOME || join(home, ".config");
  if (base === "cache") return environment.XDG_CACHE_HOME || join(home, ".cache");
  return environment.XDG_DATA_HOME || join(home, ".local", "share");
}
