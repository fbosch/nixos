import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import type { HostProcessError } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";
import type { HelperArgument } from "./provider.mts";
import type { JsonLinesCapability } from "./policy.mts";
import { awaitHelperEndpoint, scopedHelper } from "./private.mts";

/**
 * Start an IPC filter helper for `capability` and expose its private endpoint to the session.
 * The helper stops when the enclosing scope closes; accepted deliveries and cleanup messages
 * each get the capability's upstream deadline first.
 */
/** `launch` is provider data the helper hands to the provider's `serve`; it must be JSON-serializable. */
export function filterHelper(environment: Environment, home: string, capability: JsonLinesCapability, launch: unknown): Effect.Effect<Environment, HostProcessError, Scope.Scope> {
  return Effect.gen(function* () {
    let startupError = "";
    const grace = 2 * capability.limits.upstreamTimeoutMs + 1000;
    const helper = yield* scopedHelper(() => {
      const child = spawn(process.execPath, [fileURLToPath(new URL("./helper.mts", import.meta.url)), JSON.stringify({ capability, home, launch } satisfies HelperArgument)], {
        env: {}, stdio: ["pipe", "pipe", "pipe"],
      });
      child.stderr.on("data", (chunk: Buffer) => { startupError = (startupError + chunk.toString()).slice(-2048); });
      return child;
    }, { termMs: grace, killMs: grace + 2000 });
    const endpoint = yield* awaitHelperEndpoint(helper, home, { name: "IPC filter helper", timeoutMs: 5000, diagnostics: () => startupError });
    return { ...environment, [capability.socketEnvironment]: endpoint };
  });
}
