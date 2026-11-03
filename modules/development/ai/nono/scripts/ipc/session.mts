import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import { type HostProcessError, LaunchPrerequisiteError, type SandboxError } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";
import { selectCapabilities, type CapabilityRegistry, type JsonLinesCapability } from "./policy.mts";
import { filterHelper } from "./helper-launch.mts";
import { herdrReporter } from "../herdr/bootstrap.mts";
import { desktopBroker } from "../desktop/bootstrap.mts";

function inheritedSocket(environment: Environment, inherited: Environment, home: string, cwd: string, capability: JsonLinesCapability): Effect.Effect<Environment, HostProcessError | LaunchPrerequisiteError, Scope.Scope> {
  return Effect.gen(function* () {
    const bound = { ...environment };
    delete bound[capability.socketEnvironment];
    const upstream = inherited[capability.socketEnvironment];
    if (!upstream) return bound;
    if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) return yield* new LaunchPrerequisiteError({ message: `Inherited IPC endpoint must be an existing absolute Unix socket: ${capability.socketEnvironment}` });
    return yield* filterHelper(bound, home, capability, {
      upstream: realpathSync(upstream), context: { cwd: realpathSync(cwd), home: realpathSync(home), uid: process.getuid!() },
    });
  });
}

/**
 * Start a filter helper for every JSON-lines capability of `profile`, in manifest order. The
 * helpers stop in reverse order when the enclosing scope closes.
 */
export function ipcCapabilities(environment: Environment, inherited: Environment, home: string, cwd: string, agentDir: string, args: readonly string[], registry: CapabilityRegistry, profile: "ordinary" | "restricted"): Effect.Effect<Environment, HostProcessError | SandboxError, Scope.Scope> {
  return Effect.gen(function* () {
    const selected = Object.values(selectCapabilities(registry, profile)).filter((capability): capability is JsonLinesCapability & { backend: "json-lines" } => capability.backend === "json-lines");
    const activeVariables = new Set(selected.map(capability => capability.socketEnvironment));
    let current = { ...environment };
    if (profile === "restricted") {
      for (const capability of Object.values(registry.capabilities)) {
        if (capability.backend === "json-lines" && !activeVariables.has(capability.socketEnvironment)) delete current[capability.socketEnvironment];
      }
    }
    // The restricted profile never passes inherited Herdr access through unfiltered.
    if (profile === "restricted" && !selected.some(capability => capability.provider === "herdr")) {
      current = yield* herdrReporter(current, inherited, home, cwd, agentDir, args, null);
    }
    for (const capability of selected) {
      if (capability.provider === "herdr") current = yield* herdrReporter(current, inherited, home, cwd, agentDir, args, capability);
      else if (capability.provider === "desktop") current = yield* desktopBroker(current, inherited, home, capability);
      else current = yield* inheritedSocket(current, inherited, home, cwd, capability);
    }
    return current;
  });
}
