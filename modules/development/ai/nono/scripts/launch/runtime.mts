import { mkdirSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import type { Environment } from "../shared/types.mts";

function sandboxRuntimeEnvironment(home: string): Environment {
  const cache = join(home, ".cache", "pi");
  return {
    PI_LOCKFILE_DIR: join(cache, "locks"),
    GH_CONFIG_DIR: join(cache, "gh"),
    npm_config_cache: join(cache, "npm"),
    UV_CACHE_DIR: join(cache, "uv"),
    UV_PYTHON_INSTALL_DIR: join(cache, "uv-python"),
    UV_TOOL_DIR: join(cache, "uv-tools"),
  };
}

export function prepareSandboxRuntime(home: string): void {
  // Landlock grants must resolve these paths before the sandbox starts.
  for (const path of Object.values(sandboxRuntimeEnvironment(home))) {
    mkdirSync(path!, { recursive: true, mode: 0o700 });
  }
}

export function prepareRuntimeLocks(home: string): string {
  const directory = sandboxRuntimeEnvironment(home).PI_LOCKFILE_DIR!;
  mkdirSync(directory, { recursive: true, mode: 0o700 });
  return directory;
}

export function sandboxRuntimeCommand(home: string, rawPi: string, envBinary: string): string[] {
  // Set child-only config after confinement; supervisor capture keeps the real store.
  const environment = {
    ...sandboxRuntimeEnvironment(home),
    // A nested sandbox launch must not retain a parent raw-launch notice.
    PI_NONO_MODE: "sandboxed",
    // Reload code from protected sources, never from a writable cache left by a previous session.
    JITI_FS_CACHE: "false",
    // Nono strips Node options; restore only this fixed warning filter after confinement.
    NODE_OPTIONS: "--disable-warning=UNDICI-EHPA",
  };
  return [envBinary, "--", ...Object.entries(environment).map(([name, value]) => `${name}=${value}`), rawPi];
}

export function prepareJitiCache(temporaryDirectory: string = tmpdir(), platform: NodeJS.Platform = process.platform): void {
  // Landlock grants bind existing paths; create the cache before nono resolves the profile.
  if (platform === "linux") mkdirSync(join(temporaryDirectory, "jiti"), { recursive: true, mode: 0o700 });
}

export function prepareNpmCache(home: string = homedir()): void {
  // Like Jiti's cache, these narrow profile paths must exist before Landlock grants are built.
  for (const directory of ["_cacache", "_logs"]) {
    mkdirSync(join(home, ".npm", directory), { recursive: true, mode: 0o700 });
  }
}
