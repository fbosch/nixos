import { lstatSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

const tokenNames = [
  "GH_TOKEN", "GITHUB_TOKEN", "GITHUB_PERSONAL_ACCESS_TOKEN",
  "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN",
];

export function prepareGithubEnvironment(inherited, loaded, home) {
  // The capture process inherits nono's environment. A real token in any alias would
  // remain readable if nono skipped the route, so never pass one to the supervisor.
  if (tokenNames.some((name) => inherited[name] || loaded[name])) {
    throw new Error("GitHub token environment variables cannot be passed to the Pi sandbox; use gh auth login for supervisor-side capture");
  }
  const environment = { ...loaded };
  for (const name of Object.keys(environment)) {
    if (tokenNames.includes(name) || name.startsWith("NONO_")) delete environment[name];
  }
  delete environment.GH_DEBUG;
  delete environment.DEBUG;
  // The project may set these via direnv; host-side gh must use the user's fixed store.
  environment.GH_CONFIG_DIR = join(home, ".config", "gh");
  delete environment.GH_HOST;
  delete environment.GITHUB_HOST;
  return environment;
}

export function direnvGithubEnvironment(environment) {
  const safe = { ...environment };
  for (const name of Object.keys(safe)) {
    if (tokenNames.includes(name) || name.startsWith("NONO_")) delete safe[name];
  }
  return safe;
}

function canonical(path) {
  if (!isAbsolute(path)) throw new Error("GitHub credential grant path must be absolute");
  let ancestor = resolve(path);
  const missing = [];
  for (;;) {
    let exists = false;
    try {
      lstatSync(ancestor);
      exists = true;
    } catch (error) {
      if (error.code !== "ENOENT") throw new Error("Cannot resolve GitHub credential grant path", { cause: error });
      const parent = dirname(ancestor);
      if (parent === ancestor) throw new Error("Cannot resolve GitHub credential grant path", { cause: error });
      missing.push(ancestor.slice(parent.length + (parent === sep ? 0 : 1)));
      ancestor = parent;
    }
    if (exists) {
      try {
        return join(realpathSync(ancestor), ...missing.reverse());
      } catch (error) {
        throw new Error("Cannot resolve GitHub credential grant path", { cause: error });
      }
    }
  }
}

function overlaps(left, right) {
  const remainder = relative(left, right);
  return remainder === "" || (remainder !== ".." && !remainder.startsWith(`..${sep}`) && !isAbsolute(remainder));
}

export function assertGithubCredentialGrants(args, cwd, home) {
  const store = join(home, ".config", "gh");
  const protectedPaths = [canonical(store)];
  const hosts = join(store, "hosts.yml");
  let entry;
  try {
    entry = lstatSync(hosts);
  } catch (error) {
    if (error.code !== "ENOENT") throw new Error("Cannot inspect GitHub credential store", { cause: error });
  }
  if (entry) {
    if (entry.isSymbolicLink()) protectedPaths.push(canonical(hosts));
    else if (!entry.isFile() || entry.nlink !== 1) {
      throw new Error("GitHub credential file must be a regular file without hard links");
    }
  }
  const flags = new Set(["--allow", "--read", "--allow-file", "--read-file", "--allow-unix-socket", "--read-unix-socket", "--bypass-protection"]);
  const paths = [cwd];
  for (let index = 0; index < args.length && args[index] !== "--"; index++) {
    if (flags.has(args[index])) paths.push(args[++index]);
  }
  for (const path of paths) {
    if (typeof path !== "string") throw new Error("Missing GitHub credential grant path");
    const grant = canonical(path);
    if (protectedPaths.some((protectedPath) => overlaps(grant, protectedPath) || overlaps(protectedPath, grant))) {
      throw new Error("GitHub credential store overlaps a Pi sandbox grant");
    }
  }
}
