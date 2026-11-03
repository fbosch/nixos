import * as Effect from "effect/Effect";
import { lstatSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import type { Environment, ErrnoError, NonoProfile } from "../shared/types.mts";
import { GrantConflictError, InvalidConfigError, UnsafeFileError, attempt, type SandboxError } from "../shared/errors.mts";
import { grantedPaths, type GrantFlag, type GrantPlan } from "../shared/grant-plan.mts";

export function canonicalCredentialPath(path: string, label: string): string {
  if (!isAbsolute(path)) throw new InvalidConfigError({ message: `${label} credential grant path must be absolute` });
  let ancestor = resolve(path);
  const missing: string[] = [];
  for (;;) {
    let exists = false;
    try {
      lstatSync(ancestor);
      exists = true;
    } catch (error) {
      if ((error as ErrnoError).code !== "ENOENT") throw new UnsafeFileError({ message: `Cannot resolve ${label} credential grant path`, cause: error });
      const parent = dirname(ancestor);
      if (parent === ancestor) throw new UnsafeFileError({ message: `Cannot resolve ${label} credential grant path`, cause: error });
      missing.push(ancestor.slice(parent.length + (parent === sep ? 0 : 1)));
      ancestor = parent;
    }
    if (exists) {
      try {
        return join(realpathSync(ancestor), ...missing.reverse());
      } catch (error) {
        throw new UnsafeFileError({ message: `Cannot resolve ${label} credential grant path`, cause: error });
      }
    }
  }
}

function overlaps(left: string, right: string): boolean {
  const remainder = relative(left, right);
  return remainder === "" || (remainder !== ".." && !remainder.startsWith(`..${sep}`) && !isAbsolute(remainder));
}

// Every grant that can reach a file's contents. Socket binds create new endpoints instead.
const credentialReachingFlags: readonly GrantFlag[] = ["--allow", "--read", "--allow-file", "--read-file", "--allow-unix-socket", "--read-unix-socket", "--bypass-protection"];

function assertCredentialGrantsSync(plan: GrantPlan, cwd: string, home: string, environment: Environment, profile: NonoProfile, protectedPaths: readonly string[], label: string): void {
  const paths: string[] = [cwd];
  // Check declared profile grants too: a project-selected TMPDIR must not expose the store.
  const filesystem = profile.filesystem ?? {};
  for (const key of ["allow", "read", "write", "unix_socket", "bypass_protection"] as const) {
    for (const entry of filesystem[key] ?? []) {
      const value = typeof entry === "string" ? entry : entry.path;
      const expanded = value.replace(/\$(?:\{([A-Za-z_][A-Za-z0-9_]*)\}|([A-Za-z_][A-Za-z0-9_]*))/g, (_, braced: string | undefined, bare: string | undefined) => {
        const name = braced || bare!;
        const variable = name === "HOME" ? home : environment[name];
        if (typeof variable !== "string" || variable === "") throw new InvalidConfigError({ message: `Missing ${label} credential profile path variable` });
        return variable;
      });
      paths.push(expanded);
    }
  }
  paths.push(...grantedPaths(plan, credentialReachingFlags));
  for (const path of paths) {
    const grant = canonicalCredentialPath(path, label);
    if (protectedPaths.some((protectedPath) => overlaps(grant, protectedPath) || overlaps(protectedPath, grant))) {
      throw new GrantConflictError({ message: `${label} credential store overlaps a Pi sandbox grant` });
    }
  }
}

/** Fail when any launcher or profile grant overlaps a protected credential path. */
export function assertCredentialGrants(plan: GrantPlan, cwd: string, home: string, environment: Environment, profile: NonoProfile, protectedPaths: readonly string[], label: string): Effect.Effect<void, SandboxError> {
  return attempt(() => assertCredentialGrantsSync(plan, cwd, home, environment, profile, protectedPaths, label));
}
