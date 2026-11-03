import * as Effect from "effect/Effect";
import { readFileSync, realpathSync, statSync, existsSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { InvalidConfigError, LaunchPrerequisiteError, attempt } from "../shared/errors.mts";
import { expandTilde } from "../shared/paths.mts";
import type { Environment, ErrnoError } from "../shared/types.mts";
import type { IpcProvider } from "../ipc/provider.mts";
import { createReportValidator, reportingContext, type HerdrAuthority } from "./protocol.mts";
import { createHerdrHandler } from "./reader.mts";

/** Pi settings fields read here; Pi validates the rest. */
interface PiSettings {
  sessionDir?: unknown;
}

function option(args: readonly string[], name: string): string | undefined {
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--") break;
    if (args[index]!.startsWith(`${name}=`)) return args[index]!.slice(name.length + 1);
    if (args[index] === name) {
      if (!args[index + 1] || args[index + 1]!.startsWith("--")) throw new InvalidConfigError({ message: `${name} requires a value` });
      return args[index + 1];
    }
  }
}

function settingsSessionDirectory(path: string): PiSettings {
  if (!existsSync(path)) return {};
  if (statSync(path).size > 1024 * 1024) throw new InvalidConfigError({ message: "Pi settings exceed the reporting bootstrap limit" });
  const input = readFileSync(path, "utf8").replace(/^\uFEFF/, "");
  let value: PiSettings;
  try {
    value = JSON.parse(input);
  } catch (cause) {
    throw new InvalidConfigError({ message: `Invalid Pi settings JSON: ${path}`, cause });
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new InvalidConfigError({ message: "Pi settings must be a JSON object" });
  return value;
}

function canonicalFutureDirectory(path: string): string {
  try { return realpathSync(path); }
  catch (error) {
    if ((error as ErrnoError).code !== "ENOENT") throw error;
    return join(canonicalFutureDirectory(dirname(path)), basename(path));
  }
}

function sessionDirectory(cwd: string, agentDir: string, args: readonly string[], environment: Environment, home: string): string {
  const expand = (path: string) => resolve(cwd, expandTilde(path, home));
  const global = settingsSessionDirectory(join(agentDir, "settings.json"));
  const project = settingsSessionDirectory(join(cwd, ".pi", "settings.json"));
  const configured = Object.hasOwn(project, "sessionDir") ? project.sessionDir : global.sessionDir;
  const selected = option(args, "--session-dir") || environment.PI_CODING_AGENT_SESSION_DIR || configured;
  if (selected != null && (typeof selected !== "string" || selected.length > 4096 || selected.includes("\0"))) throw new InvalidConfigError({ message: "Invalid Pi session directory" });
  const session = option(args, "--session");
  const file = session && (session.includes("/") || session.includes("\\") || session.endsWith(".jsonl"));
  const directory = selected ? expand(selected as string) : file ? dirname(expand(session))
    : join(agentDir, "sessions", `--${resolve(cwd).replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`);
  // Capture a future path without creating host directories on behalf of mutable settings.
  return canonicalFutureDirectory(directory);
}


const herdrVariables = ["HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID", "PI_NVIM_HERDR_PANE_ID", "HERDR_AGENT"];

function scrub(environment: Environment): Environment {
  const disabled = { ...environment };
  for (const name of herdrVariables) delete disabled[name];
  return disabled;
}

/**
 * Herdr reporting for the pane Pi runs in. The helper accepts only reports and passive reads for
 * that pane's workspace. Without an inherited Herdr session the provider only removes Herdr variables.
 */
export const herdrProvider: IpcProvider = {
  start: (environment, { inherited, home, cwd, agentDir, args, startHelper }, capability) => Effect.gen(function* () {
    const pane = inherited.PI_NVIM_HERDR_PANE_ID || inherited.HERDR_PANE_ID;
    const upstream = inherited.HERDR_SOCKET_PATH;
    if (inherited.HERDR_ENV !== "1" || !pane || !upstream) return scrub(environment);
    const identity = /^(w[A-Za-z0-9_-]+):p[A-Za-z0-9_-]+$/.exec(pane);
    if (!identity) return yield* new InvalidConfigError({ message: "Invalid inherited Herdr pane identity" });
    if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) return yield* new LaunchPrerequisiteError({ message: "Inherited Herdr endpoint must be an existing Unix socket" });
    const authority: HerdrAuthority = {
      upstream: realpathSync(upstream), pane, embedded: Boolean(inherited.PI_NVIM_HERDR_PANE_ID),
      sessionDirectory: yield* attempt(() => sessionDirectory(cwd, agentDir, args, environment, home)),
    };
    const bound: Environment = { ...environment, HERDR_ENV: "1", HERDR_WORKSPACE_ID: identity[1] };
    for (const name of ["HERDR_PANE_ID", "PI_NVIM_HERDR_PANE_ID"]) {
      if (inherited[name] === undefined) delete bound[name];
      else bound[name] = inherited[name];
    }
    return yield* startHelper(bound, capability, authority);
  }),
  serve: (launch, capability) => {
    const authority = launch as HerdrAuthority;
    return {
      context: reportingContext(authority), upstream: authority.upstream,
      validate: createReportValidator(authority, capability),
      deliver: createHerdrHandler(authority, capability),
    };
  },
  scrub,
};
