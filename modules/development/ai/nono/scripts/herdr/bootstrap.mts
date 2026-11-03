import { readFileSync, realpathSync, statSync, existsSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { defaultCapabilities, selectCapabilities, type JsonLinesCapability } from "../ipc/policy.mts";
import { withFilterHelper } from "../ipc/helper-launch.mts";
import { expandTilde } from "../shared/paths.mts";
import type { Environment, ErrnoError, SessionStep } from "../shared/types.mts";
import type { HerdrAuthority } from "./protocol.mts";

/** Pi settings fields read here; Pi validates the rest. */
interface PiSettings {
  sessionDir?: unknown;
}

function option(args: readonly string[], name: string): string | undefined {
  for (let index = 0; index < args.length; index++) {
    if (args[index] === "--") break;
    if (args[index]!.startsWith(`${name}=`)) return args[index]!.slice(name.length + 1);
    if (args[index] === name) {
      if (!args[index + 1] || args[index + 1]!.startsWith("--")) throw new Error(`${name} requires a value`);
      return args[index + 1];
    }
  }
}

function settingsSessionDirectory(path: string): PiSettings {
  if (!existsSync(path)) return {};
  if (statSync(path).size > 1024 * 1024) throw new Error("Pi settings exceed the reporting bootstrap limit");
  const input = readFileSync(path, "utf8").replace(/^\uFEFF/, "");
  let value: PiSettings;
  try {
    value = JSON.parse(input);
  } catch (cause) {
    throw new Error(`Invalid Pi settings JSON: ${path}`, { cause });
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Pi settings must be a JSON object");
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
  if (selected != null && (typeof selected !== "string" || selected.length > 4096 || selected.includes("\0"))) throw new Error("Invalid Pi session directory");
  const session = option(args, "--session");
  const file = session && (session.includes("/") || session.includes("\\") || session.endsWith(".jsonl"));
  const directory = selected ? expand(selected as string) : file ? dirname(expand(session))
    : join(agentDir, "sessions", `--${resolve(cwd).replace(/^[/\\]/, "").replace(/[/\\:]/g, "-")}--`);
  // Capture a future path without creating host directories on behalf of mutable settings.
  return canonicalFutureDirectory(directory);
}


/** `capability: null` disables reporting but still removes inherited Herdr variables. */
export async function withHerdrReporter<T>(environment: Environment, inherited: Environment, home: string, cwd: string, agentDir: string, args: readonly string[], run: SessionStep<T>, capability: JsonLinesCapability | null = selectCapabilities(defaultCapabilities, "restricted")["herdr-reporting"] as JsonLinesCapability): Promise<T> {
  const pane = inherited.PI_NVIM_HERDR_PANE_ID || inherited.HERDR_PANE_ID;
  const upstream = inherited.HERDR_SOCKET_PATH;
  if (capability === null || inherited.HERDR_ENV !== "1" || !pane || !upstream) {
    const disabled = { ...environment };
    for (const name of ["HERDR_ENV", "HERDR_SOCKET_PATH", "HERDR_PANE_ID", "PI_NVIM_HERDR_PANE_ID", "HERDR_AGENT"]) delete disabled[name];
    return run(disabled);
  }
  const identity = /^(w[A-Za-z0-9_-]+):p[A-Za-z0-9_-]+$/.exec(pane);
  if (!identity) throw new Error("Invalid inherited Herdr pane identity");
  if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) throw new Error("Inherited Herdr endpoint must be an existing Unix socket");
  const authority: HerdrAuthority = {
    upstream: realpathSync(upstream), pane, embedded: Boolean(inherited.PI_NVIM_HERDR_PANE_ID),
    sessionDirectory: sessionDirectory(cwd, agentDir, args, environment, home),
  };
  const bound: Environment = { ...environment, HERDR_ENV: "1", HERDR_WORKSPACE_ID: identity[1] };
  for (const name of ["HERDR_PANE_ID", "PI_NVIM_HERDR_PANE_ID"]) {
    if (inherited[name] === undefined) delete bound[name];
    else bound[name] = inherited[name];
  }
  return withFilterHelper(bound, home, capability, { authority }, run);
}
