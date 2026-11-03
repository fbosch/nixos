import { spawnSync } from "node:child_process";
import { existsSync, statSync, type Stats } from "node:fs";
import { delimiter, isAbsolute, join, resolve } from "node:path";
import { stripVTControlCharacters } from "node:util";
import { expandTilde, isRecord } from "../shared/paths.mts";
import type { Environment, ErrnoError } from "../shared/types.mts";

export function loadProjectEnvironment(cwd: string, environment: Environment, direnv: string, run: typeof spawnSync = spawnSync): Environment {
  const envrc = join(cwd, ".envrc");
  let entry: Stats;
  try {
    entry = statSync(envrc);
  } catch (error) {
    if ((error as ErrnoError).code === "ENOENT") return { ...environment };
    throw error;
  }
  if (!entry.isFile()) throw new Error("Project .envrc must be a file");
  if (!isAbsolute(direnv) || !existsSync(direnv) || !statSync(direnv).isFile()) {
    throw new Error("Packaged direnv executable missing");
  }

  // Collect the diff before confinement; the launcher falls back to the sanitized inherited environment on failure.
  // Caller-controlled shell/Node preloads must not execute in this trusted bootstrap.
  const loaderEnvironment = { ...environment };
  for (const name of ["BASH_ENV", "ENV", "NODE_OPTIONS", "NODE_PATH"]) delete loaderEnvironment[name];
  const result = run(direnv, ["export", "json"], {
    cwd,
    env: loaderEnvironment,
    encoding: "utf8",
    timeout: 120_000,
    maxBuffer: 16 * 1024 * 1024,
  });
  // Direnv can exit zero after evaluation errors; inspect severity and shell diagnostics, not keywords.
  const diagnostics = stripVTControlCharacters(result.stderr || "");
  if (result.error || result.status !== 0 ||
      /^[ \t]*(?:(?:direnv|nix|devenv):[ \t]*)?(?:error|fatal)(?:[ \t:]|$)/im.test(diagnostics) ||
      /^[^:\r\n]+:[ \t]*(?:line[ \t]+)?\d+:(?![ \t]*warning(?:[ \t:]|$))/im.test(diagnostics)) {
    throw new Error("Project direnv environment load failed");
  }

  let exported: unknown;
  try {
    exported = result.stdout.trim() === "" ? {} : JSON.parse(result.stdout);
  } catch {
    throw new Error("Project direnv export is not valid JSON");
  }
  if (!isRecord(exported)) throw new Error("Project direnv export must be an object");

  const loaded = { ...environment };
  for (const [name, value] of Object.entries(exported)) {
    if (value === null) delete loaded[name];
    else if (typeof value === "string") loaded[name] = value;
    else throw new Error("Project direnv export contains an invalid environment value");
  }
  delete loaded.NODE_OPTIONS;
  delete loaded.NODE_PATH;
  return loaded;
}

export function configurePiPaths(environment: Environment, home: string, entryBin: string | undefined): string {
  const configuredAgent = environment.PI_CODING_AGENT_DIR || join(home, ".pi", "agent");
  const agentDir = resolve(expandTilde(configuredAgent, home));
  environment.PI_CODING_AGENT_DIR = agentDir;
  const managedBin = join(agentDir, "bin");
  const legacyBins = new Set([managedBin, join(home, ".pi", "agent", "bin"), join(home, "dotfiles", ".pi", "agent", "bin")]);
  const pathEntries = (environment.PATH || "").split(delimiter).filter(Boolean);
  // Pure routing, not a sandbox prerequisite: keep writable launchers behind the immutable entry in both modes.
  // Keeping the managed bin present prevents the shell helper from prepending it again.
  environment.PATH = [
    ...(entryBin ? [entryBin] : []),
    ...pathEntries.filter(path => path !== entryBin && !legacyBins.has(resolve(path))),
    ...new Set(pathEntries.filter(path => legacyBins.has(resolve(path)) && resolve(path) !== managedBin)),
    managedBin,
  ].join(delimiter);
  return agentDir;
}
