import * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import { filterHelper } from "../ipc/helper-launch.mts";
import type { JsonLinesCapability } from "../ipc/policy.mts";
import type { HostProcessError } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";
import { desktopAuthority } from "./broker.mts";

/** Start the desktop filter helper when the launch environment carries desktop authority. */
export function desktopBroker(environment: Environment, inherited: Environment, home: string, capability: JsonLinesCapability): Effect.Effect<Environment, HostProcessError, Scope.Scope> {
  const bound = { ...environment };
  delete bound[capability.socketEnvironment];
  const authority = desktopAuthority(inherited);
  if (!authority) return Effect.succeed(bound);
  return filterHelper(bound, home, capability, { desktop: authority });
}
