import { withFilterHelper } from "../ipc/helper-launch.mts";
import type { JsonLinesCapability } from "../ipc/policy.mts";
import type { Environment, SessionStep } from "../shared/types.mts";
import { desktopAuthority } from "./broker.mts";

/** Start the desktop filter helper when the launch environment carries desktop authority. */
export async function withDesktopBroker<T>(environment: Environment, inherited: Environment, home: string, capability: JsonLinesCapability, run: SessionStep<T>): Promise<T> {
  const bound = { ...environment };
  delete bound[capability.socketEnvironment];
  const authority = desktopAuthority(inherited);
  if (!authority) return run(bound);
  return withFilterHelper(bound, home, capability, { desktop: authority }, run);
}
