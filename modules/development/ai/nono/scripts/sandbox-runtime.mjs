import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

function sandboxRuntimeEnvironment(home) {
  const cache = join(home, ".cache", "pi");
  return {
    GH_CONFIG_DIR: join(cache, "gh"),
    npm_config_cache: join(cache, "npm"),
    UV_CACHE_DIR: join(cache, "uv"),
    UV_PYTHON_INSTALL_DIR: join(cache, "uv-python"),
    UV_TOOL_DIR: join(cache, "uv-tools"),
  };
}

export function prepareSandboxRuntime(home) {
  // Landlock grants must resolve these paths before the sandbox starts.
  for (const path of Object.values(sandboxRuntimeEnvironment(home))) {
    mkdirSync(path, { recursive: true, mode: 0o700 });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [rawPi, ...args] = process.argv.slice(2);
  // Only the child uses separate CLI config; supervisor-side capture keeps the real store.
  const environment = { ...process.env, ...sandboxRuntimeEnvironment(homedir()) };
  // Nono strips Node options; restore only this fixed warning filter after confinement.
  environment.NODE_OPTIONS = "--disable-warning=UNDICI-EHPA";
  process.execve(rawPi, [rawPi, ...args], environment);
}
