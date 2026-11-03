import * as Cause from "effect/Cause";
import * as Data from "effect/Data";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";

// Every check fails closed with one of these. Messages are user-facing and stay stable: tests and
// operators match on them.

interface Details {
  readonly message: string;
  readonly cause?: unknown;
}

/** A sandbox grant would reach a path that must stay host-only, protected or private. */
export class GrantConflictError extends Data.TaggedError("GrantConflictError")<Details> {}

/** A filesystem object is not what the policy requires: wrong type, owner, mode, link or location. */
export class UnsafeFileError extends Data.TaggedError("UnsafeFileError")<Details> {}

/** Configuration or launch input is malformed: settings, declarations, profile or environment. */
export class InvalidConfigError extends Data.TaggedError("InvalidConfigError")<Details> {}

/** A Nix-provided executable, profile or inherited socket that the launch needs is missing or unusable. */
export class LaunchPrerequisiteError extends Data.TaggedError("LaunchPrerequisiteError")<Details> {}

/**
 * A host helper process (model executor, IPC filter, credential proxy) failed to start, reported
 * an invalid endpoint, or stopped while Pi was running. Not a SandboxError: policy checks never
 * raise it.
 */
export class HostProcessError extends Data.TaggedError("HostProcessError")<Details> {}

/** Wrap a rejected helper promise, keeping its message for users and tests. */
export function hostProcessError(cause: unknown): HostProcessError {
  return cause instanceof HostProcessError ? cause : new HostProcessError({ message: cause instanceof Error ? cause.message : String(cause), cause });
}

export type SandboxError = GrantConflictError | UnsafeFileError | InvalidConfigError | LaunchPrerequisiteError;

function isSandboxError(error: unknown): error is SandboxError {
  return error instanceof GrantConflictError || error instanceof UnsafeFileError ||
    error instanceof InvalidConfigError || error instanceof LaunchPrerequisiteError;
}

/**
 * Run synchronous policy code as an Effect. Sandbox errors it throws become typed failures; any
 * other exception, such as an unexpected filesystem error, remains a defect.
 */
export function attempt<A>(check: () => A): Effect.Effect<A, SandboxError> {
  return Effect.suspend(() => {
    try {
      return Effect.succeed(check());
    } catch (error) {
      if (isSandboxError(error)) return Effect.fail(error);
      throw error;
    }
  });
}

/** Run an Effect at a synchronous boundary and rethrow its original error, typed or defect. */
export function runSyncOrThrow<A, E>(effect: Effect.Effect<A, E>): A {
  const exit = Effect.runSyncExit(effect);
  if (Exit.isSuccess(exit)) return exit.value;
  throw Cause.squash(exit.cause);
}
