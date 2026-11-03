import type * as Scope from "effect/Scope";
import * as Effect from "effect/Effect";
import { createHash } from "node:crypto";
import { closeSync, constants, existsSync, fchmodSync, fstatSync, lstatSync, mkdirSync, openSync, readdirSync, realpathSync, rmSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";
import type { Environment } from "../shared/types.mts";
import { privateIpcDirectory, privateIpcPrefix } from "./private.mts";
import { InvalidConfigError, LaunchPrerequisiteError, type SandboxError, UnsafeFileError, attempt } from "../shared/errors.mts";

function waylandSocket(environment: Environment): string | undefined {
  const display = environment.WAYLAND_DISPLAY;
  if (!display) return undefined;
  const runtime = environment.XDG_RUNTIME_DIR;
  if (!isAbsolute(display) && (!/^[A-Za-z0-9._-]{1,64}$/.test(display) || !runtime || !isAbsolute(runtime))) {
    throw new InvalidConfigError({ message: "Wayland display must be absolute or a display name under an absolute XDG_RUNTIME_DIR" });
  }
  // The check above requires an absolute runtime whenever the display is a bare name.
  const socket = realpathSync(isAbsolute(display) ? display : join(runtime!, display));
  if (!statSync(socket).isSocket()) throw new LaunchPrerequisiteError({ message: "Wayland display must point to a Unix socket" });
  return socket;
}

/**
 * Session-private service state: a fresh browser-daemon directory, removed when the enclosing
 * scope closes, and the compositor captured before project environment loading.
 */
export function sessionServices(environment: Environment, inherited: Environment, home: string): Effect.Effect<Environment, SandboxError, Scope.Scope> {
  return Effect.gen(function* () {
    const display = yield* attempt(() => waylandSocket(inherited));
    const browser = yield* Effect.acquireRelease(
      attempt(() => privateIpcDirectory(home, "b-")),
      (browser) => Effect.sync(() => rmSync(browser, { recursive: true, force: true })),
    );
    const bound: Environment = { ...environment, AGENT_BROWSER_SOCKET_DIR: browser, PI_LENS_WARM_ATTACH: "0" };
    // Capture the original compositor, not a socket selected by project environment loading.
    if (display) bound.WAYLAND_DISPLAY = display;
    else delete bound.WAYLAND_DISPLAY;
    // agent-browser 0.41 resolves this override before its global daemon directory.
    // An empty new directory prevents reuse of a host daemon, even for the same Pi session ID.
    for (const name of ["AGENT_BROWSER_NAMESPACE", "AGENT_BROWSER_CDP", "AGENT_BROWSER_AUTO_CONNECT", "AGENT_BROWSER_PROFILE", "AGENT_BROWSER_SESSION_NAME"]) delete bound[name];
    return bound;
  });
}

function projectDotfile(cwd: string, home: string, environment: Environment): string | undefined {
  const directory = realpathSync(cwd);
  if (environment.DEVENV_ROOT && isAbsolute(environment.DEVENV_ROOT)) {
    const root = realpathSync(environment.DEVENV_ROOT);
    if (directory === root || directory.startsWith(root + sep)) {
      const dotfile = environment.DEVENV_DOTFILE || join(root, ".devenv");
      if (!isAbsolute(dotfile)) throw new InvalidConfigError({ message: "DEVENV_DOTFILE must be absolute" });
      // Devenv 2.4 resolves the parent, not the leaf; the exported path already includes profiles.
      return join(realpathSync(dirname(dotfile)), basename(dotfile));
    }
  }
  for (let path = directory; ; path = dirname(path)) {
    if (existsSync(join(path, "devenv.nix"))) return join(path, ".devenv");
    if (path === home || dirname(path) === path) return undefined;
  }
}

export function devenvRuntime(cwd: string, home: string, environment: Environment): string | undefined {
  const dotfile = projectDotfile(cwd, home, environment);
  if (!dotfile) return undefined;
  // Pinned devenv-core/src/paths.rs: DEVENV_RUNTIME is an output, never an override.
  const hash = createHash("sha256").update(dotfile).digest("hex").slice(0, 7);
  const base = environment.XDG_RUNTIME_DIR || "/tmp";
  if (!isAbsolute(base)) throw new InvalidConfigError({ message: "XDG_RUNTIME_DIR must be absolute" });
  return join(base, `devenv-${hash}`);
}

function serviceSocketArgumentsSync(cwd: string, home: string, environment: Environment, restricted: boolean): string[] {
  if (!restricted) return [];
  const args: string[] = [];
  // Direct compositor access deliberately permits all exposed Wayland protocols, including clipboard reads.
  const display = waylandSocket(environment);
  if (display) args.push("--allow-unix-socket", display);
  const browser = environment.AGENT_BROWSER_SOCKET_DIR;
  if (browser) {
    const directory = realpathSync(browser);
    if (!directory.startsWith(privateIpcPrefix(home)) || !lstatSync(browser).isDirectory()) throw new UnsafeFileError({ message: "Browser IPC directory must belong to this Pi launch" });
    args.push("--allow", directory, "--allow-unix-socket-dir-bind", directory);
  }
  const runtime = devenvRuntime(cwd, home, environment);
  if (!runtime) return args;
  // Native process-manager endpoints are created lazily under processes/.
  mkdirSync(runtime, { mode: 0o700, recursive: true });
  const entry = lstatSync(runtime);
  const invalidRuntime = "Devenv runtime must be a private, user-owned directory without symlinks";
  if (!entry.isDirectory() || entry.uid !== process.getuid!()) throw new UnsafeFileError({ message: invalidRuntime });
  if ((entry.mode & 0o077) !== 0) {
    // Match Devenv's create_runtime_dir: secure legacy directories without following a replaced symlink.
    const descriptor = openSync(runtime, constants.O_RDONLY | constants.O_DIRECTORY | constants.O_NOFOLLOW);
    try {
      if (fstatSync(descriptor).uid !== process.getuid!()) throw new UnsafeFileError({ message: invalidRuntime });
      fchmodSync(descriptor, 0o700);
    } finally {
      closeSync(descriptor);
    }
  }
  mkdirSync(join(runtime, "processes"), { mode: 0o700, recursive: true });
  args.push("--allow", runtime, "--allow-unix-socket-dir-bind", runtime);
  // Existing service directories get direct-child grants, never a subtree grant.
  for (const entry of readdirSync(runtime, { withFileTypes: true })) {
    if (entry.isDirectory()) args.push("--allow-unix-socket-dir-bind", join(runtime, entry.name));
  }
  return args;
}

/** Socket grants for Wayland, the session's browser daemon and the project's devenv runtime. */
export function serviceSocketArguments(cwd: string, home: string, environment: Environment, restricted: boolean): Effect.Effect<string[], SandboxError> {
  return attempt(() => serviceSocketArgumentsSync(cwd, home, environment, restricted));
}
