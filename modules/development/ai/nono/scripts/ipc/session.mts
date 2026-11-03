import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { HostProcessError, SandboxError } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";
import { selectCapabilities, type CapabilityRegistry, type JsonLinesCapability } from "./policy.mts";
import { filterHelper } from "./helper-launch.mts";
import type { ProviderSession } from "./provider.mts";
import { providers } from "./providers.mts";

/**
 * Bind every JSON-lines capability of `profile`, in manifest order, through its provider. Helpers
 * stop in reverse order when the enclosing scope closes.
 */
/** The session a provider starts in, with the real filter helper. */
export function providerSession(session: Omit<ProviderSession, "startHelper">): ProviderSession {
  return { ...session, startHelper: (environment, capability, launch) => filterHelper(environment, session.home, capability, launch) };
}

export function ipcCapabilities(environment: Environment, session: ProviderSession, registry: CapabilityRegistry, profile: "ordinary" | "restricted"): Effect.Effect<Environment, HostProcessError | SandboxError, Scope.Scope> {
  return Effect.gen(function* () {
    const selected = Object.values(selectCapabilities(registry, profile)).filter((capability): capability is JsonLinesCapability & { backend: "json-lines" } => capability.backend === "json-lines");
    const activeVariables = new Set(selected.map(capability => capability.socketEnvironment));
    let current = { ...environment };
    if (profile === "restricted") {
      for (const capability of Object.values(registry.capabilities)) {
        if (capability.backend === "json-lines" && !activeVariables.has(capability.socketEnvironment)) delete current[capability.socketEnvironment];
      }
      // The restricted profile never passes an unselected provider's inherited access through unfiltered.
      for (const [name, provider] of Object.entries(providers)) {
        if (provider.scrub && !selected.some(capability => capability.provider === name)) current = provider.scrub(current);
      }
    }
    for (const capability of selected) current = yield* providers[capability.provider].start(current, session, capability);
    return current;
  });
}
