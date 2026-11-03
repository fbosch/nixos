import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Environment } from "../shared/types.mts";

/** A private, empty nono log file for this session, removed when the enclosing scope closes. */
export function nonoDiagnostics(environment: Environment): Effect.Effect<Environment, never, Scope.Scope> {
  return Effect.gen(function* () {
    const directory = yield* Effect.acquireRelease(
      Effect.sync(() => mkdtempSync(join(environment.TMPDIR || tmpdir(), "pi-nono-diagnostics-"))),
      (directory) => Effect.sync(() => rmSync(directory, { recursive: true, force: true })),
    );
    const path = join(directory, "nono.log");
    writeFileSync(path, "", { mode: 0o600, flag: "wx" });
    return { ...environment, PI_NONO_DIAGNOSTICS_FILE: path };
  });
}
