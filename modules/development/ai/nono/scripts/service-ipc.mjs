import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readdirSync, realpathSync, rmSync } from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";
import { privateIpcDirectory } from "./private-ipc.mjs";

export async function withSessionServiceEnvironment(environment, home, run) {
  const browser = privateIpcDirectory(home, "b-");
  const bound = { ...environment, AGENT_BROWSER_SOCKET_DIR: browser, PI_LENS_WARM_ATTACH: "0" };
  // agent-browser 0.41 resolves this override before its global daemon directory.
  // An empty new directory prevents reuse of a host daemon, even for the same Pi session ID.
  for (const name of ["AGENT_BROWSER_NAMESPACE", "AGENT_BROWSER_CDP", "AGENT_BROWSER_AUTO_CONNECT", "AGENT_BROWSER_PROFILE", "AGENT_BROWSER_SESSION_NAME"]) delete bound[name];
  try {
    return await run(bound);
  } finally {
    rmSync(browser, { recursive: true, force: true });
  }
}

function projectDotfile(cwd, home, environment) {
  const directory = realpathSync(cwd);
  if (environment.DEVENV_ROOT && isAbsolute(environment.DEVENV_ROOT)) {
    const root = realpathSync(environment.DEVENV_ROOT);
    if (directory === root || directory.startsWith(root + sep)) {
      const dotfile = environment.DEVENV_DOTFILE || join(root, ".devenv");
      if (!isAbsolute(dotfile)) throw new Error("DEVENV_DOTFILE must be absolute");
      // Devenv 2.4 resolves the parent, not the leaf; the exported path already includes profiles.
      return join(realpathSync(dirname(dotfile)), basename(dotfile));
    }
  }
  for (let path = directory; ; path = dirname(path)) {
    if (existsSync(join(path, "devenv.nix"))) return join(path, ".devenv");
    if (path === home || dirname(path) === path) return undefined;
  }
}

export function devenvRuntime(cwd, home, environment) {
  const dotfile = projectDotfile(cwd, home, environment);
  if (!dotfile) return undefined;
  // Pinned devenv-core/src/paths.rs: DEVENV_RUNTIME is an output, never an override.
  const hash = createHash("sha256").update(dotfile).digest("hex").slice(0, 7);
  const base = environment.XDG_RUNTIME_DIR || "/tmp";
  if (!isAbsolute(base)) throw new Error("XDG_RUNTIME_DIR must be absolute");
  return join(base, `devenv-${hash}`);
}

export function serviceSocketArguments(cwd, home, environment, restricted) {
  if (!restricted) return [];
  const args = [];
  const browser = environment.AGENT_BROWSER_SOCKET_DIR;
  if (browser) {
    const directory = realpathSync(browser);
    const base = join(realpathSync(home), ".pi-ipc") + sep;
    if (!directory.startsWith(base) || !lstatSync(browser).isDirectory()) throw new Error("Browser IPC directory must belong to this Pi launch");
    args.push("--allow", directory, "--allow-unix-socket-dir-bind", directory);
  }
  const runtime = devenvRuntime(cwd, home, environment);
  if (!runtime) return args;
  // Native process-manager endpoints are created lazily under processes/.
  mkdirSync(runtime, { mode: 0o700, recursive: true });
  const entry = lstatSync(runtime);
  if (!entry.isDirectory() || entry.uid !== process.getuid() || (entry.mode & 0o077) !== 0) throw new Error("Devenv runtime must be a private, user-owned directory without symlinks");
  mkdirSync(join(runtime, "processes"), { mode: 0o700, recursive: true });
  args.push("--allow", runtime, "--allow-unix-socket-dir-bind", runtime);
  // Existing service directories get direct-child grants, never a subtree grant.
  for (const entry of readdirSync(runtime, { withFileTypes: true })) {
    if (entry.isDirectory()) args.push("--allow-unix-socket-dir-bind", join(runtime, entry.name));
  }
  return args;
}
