import { lstatSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";

export function canonicalCredentialPath(path, label) {
  if (!isAbsolute(path)) throw new Error(`${label} credential grant path must be absolute`);
  let ancestor = resolve(path);
  const missing = [];
  for (;;) {
    let exists = false;
    try {
      lstatSync(ancestor);
      exists = true;
    } catch (error) {
      if (error.code !== "ENOENT") throw new Error(`Cannot resolve ${label} credential grant path`, { cause: error });
      const parent = dirname(ancestor);
      if (parent === ancestor) throw new Error(`Cannot resolve ${label} credential grant path`, { cause: error });
      missing.push(ancestor.slice(parent.length + (parent === sep ? 0 : 1)));
      ancestor = parent;
    }
    if (exists) {
      try {
        return join(realpathSync(ancestor), ...missing.reverse());
      } catch (error) {
        throw new Error(`Cannot resolve ${label} credential grant path`, { cause: error });
      }
    }
  }
}

function overlaps(left, right) {
  const remainder = relative(left, right);
  return remainder === "" || (remainder !== ".." && !remainder.startsWith(`..${sep}`) && !isAbsolute(remainder));
}

export function assertCredentialGrants(args, cwd, home, environment, profile, protectedPaths, label) {
  const flags = new Set(["--allow", "--read", "--allow-file", "--read-file", "--allow-unix-socket", "--read-unix-socket", "--bypass-protection"]);
  const paths = [cwd];
  // Check declared profile grants too: a project-selected TMPDIR must not expose the store.
  const filesystem = profile.filesystem ?? {};
  for (const key of ["allow", "read", "write", "unix_socket", "bypass_protection"]) {
    for (const entry of filesystem[key] ?? []) {
      const value = typeof entry === "string" ? entry : entry.path;
      const expanded = value.replace(/\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_, braced, bare) => {
        const name = braced || bare;
        const variable = name === "HOME" ? home : environment[name];
        if (typeof variable !== "string" || variable === "") throw new Error(`Missing ${label} credential profile path variable`);
        return variable;
      });
      paths.push(expanded);
    }
  }
  for (let index = 0; index < args.length && args[index] !== "--"; index++) {
    if (flags.has(args[index])) paths.push(args[++index]);
  }
  for (const path of paths) {
    if (typeof path !== "string") throw new Error(`Missing ${label} credential grant path`);
    const grant = canonicalCredentialPath(path, label);
    if (protectedPaths.some((protectedPath) => overlaps(grant, protectedPath) || overlaps(protectedPath, grant))) {
      throw new Error(`${label} credential store overlaps a Pi sandbox grant`);
    }
  }
}
