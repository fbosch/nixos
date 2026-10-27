import { mkdirSync } from "node:fs";
import { join } from "node:path";

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

export function sandboxRuntimeCommand(home, rawPi, envBinary) {
  // Set child-only config after confinement; supervisor capture keeps the real store.
  const environment = {
    ...sandboxRuntimeEnvironment(home),
    // Nono strips Node options; restore only this fixed warning filter after confinement.
    NODE_OPTIONS: "--disable-warning=UNDICI-EHPA",
  };
  // Hide the unavailable host RPC integration; authorization is also omitted by the launcher.
  return [envBinary, "-u", "PI_NVIM_SOCKET", "--", ...Object.entries(environment).map(([name, value]) => `${name}=${value}`), rawPi];
}
