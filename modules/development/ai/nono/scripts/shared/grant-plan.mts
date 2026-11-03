// A session's sandbox grants as decisions, not as nono argv. Builders return grants, the launch
// guards inspect the plan, and toArguments serializes it once. Grant order is the argument order.

/** nono flags that grant access to a path. */
export type GrantFlag =
  | "--allow" | "--read" | "--allow-file" | "--read-file"
  | "--allow-unix-socket" | "--read-unix-socket" | "--allow-unix-socket-bind" | "--allow-unix-socket-dir-bind"
  | "--bypass-protection";

export interface Grant {
  readonly flag: GrantFlag;
  readonly path: string;
}

export interface GrantPlan {
  /** Whether nono grants the whole working directory (`--allow-cwd`) instead of split grants. */
  readonly allowCwd: boolean;
  readonly grants: readonly Grant[];
}

export function grant(flag: GrantFlag, path: string): Grant {
  return { flag, path };
}

export function grantPlan(grants: readonly Grant[], allowCwd = false): GrantPlan {
  return { allowCwd, grants };
}

/** Paths of grants with any of `flags`, in grant order. */
export function grantedPaths(plan: GrantPlan, flags: readonly GrantFlag[]): string[] {
  return plan.grants.filter((entry) => flags.includes(entry.flag)).map((entry) => entry.path);
}

/** Writable grants: files and directories, without the working directory. */
export const writableFlags: readonly GrantFlag[] = ["--allow", "--allow-file"];

export function toArguments(grants: readonly Grant[]): string[] {
  return grants.flatMap((entry) => [entry.flag, entry.path]);
}
