import * as Cause from "effect/Cause";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";

// Run `use` while a scoped launcher resource is open, then close it. Failures from the resource,
// from `use` or from cleanup are rethrown as the original error, as the launcher reports them.

function unwrap(exit) {
  if (Exit.isSuccess(exit)) return exit.value;
  throw Cause.squash(exit.cause);
}

export async function withScoped(resource, use) {
  return unwrap(await Effect.runPromiseExit(Effect.scoped(Effect.flatMap(resource, (value) =>
    Effect.tryPromise({ try: async () => use(value), catch: (error) => error })))));
}

/** For resources and callbacks that never wait, such as the macOS shell profile. */
export function withScopedSync(resource, use) {
  return unwrap(Effect.runSyncExit(Effect.scoped(Effect.flatMap(resource, (value) =>
    Effect.try({ try: () => use(value), catch: (error) => error })))));
}
