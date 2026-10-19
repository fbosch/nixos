import { spawnSync } from "node:child_process";
import { isAbsolute } from "node:path";

export function loadGithubEnvironment(environment, gh, {
  credentialEnvironment = environment,
  platform = process.platform,
  run = spawnSync,
  warn = console.error,
} = {}) {
  if (!["darwin", "linux"].includes(platform) || environment.GH_TOKEN || environment.GITHUB_TOKEN) return { ...environment };
  if (!isAbsolute(gh)) throw new Error("Packaged GitHub CLI path must be absolute");

  // Credential stores remain blocked in nono. Use the inherited environment, not project-selected
  // executables/configuration, and never pass the captured token through argv or diagnostics.
  const env = { ...credentialEnvironment };
  for (const name of ["NODE_OPTIONS", "NODE_PATH", "BASH_ENV", "ENV", "GH_DEBUG", "DEBUG"]) delete env[name];
  const result = run(gh, ["auth", "token", "--hostname", "github.com"], {
    cwd: "/",
    env,
    stdio: ["ignore", "pipe", "ignore"],
    encoding: "utf8",
    timeout: 10_000,
    maxBuffer: 16 * 1024,
  });
  const token = (result.stdout || "").trim();
  if (result.error || result.status !== 0 || !token || /[\s\x00-\x1f\x7f]/.test(token)) {
    warn("pi sandbox launch: GitHub credential unavailable; GitHub MCP may require authentication");
    return { ...environment };
  }
  return { ...environment, GH_TOKEN: token };
}
