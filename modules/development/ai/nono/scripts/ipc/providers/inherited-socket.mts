import * as Effect from "effect/Effect";
import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import { LaunchPrerequisiteError } from "../../shared/errors.mts";
import { createMessageValidator, type LaunchContext } from "../policy.mts";
import type { IpcProvider } from "../provider.mts";

/** Launch data: the inherited upstream socket and the identity that bound request fields must match. */
interface InheritedLaunch {
  upstream: string;
  context: LaunchContext;
}

/** Filters a socket the launcher inherited; requests matching the capability's schema are forwarded to it. */
export const inheritedSocketProvider: IpcProvider = {
  start: (environment, { inherited, home, cwd, startHelper }, capability) => Effect.gen(function* () {
    const bound = { ...environment };
    delete bound[capability.socketEnvironment];
    const upstream = inherited[capability.socketEnvironment];
    if (!upstream) return bound;
    if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) return yield* new LaunchPrerequisiteError({ message: `Inherited IPC endpoint must be an existing absolute Unix socket: ${capability.socketEnvironment}` });
    return yield* startHelper(bound, capability, {
      upstream: realpathSync(upstream), context: { cwd: realpathSync(cwd), home: realpathSync(home), uid: process.getuid!() },
    } satisfies InheritedLaunch);
  }),
  serve: (launch, capability) => {
    const { upstream, context } = launch as InheritedLaunch;
    return { context, upstream, validate: createMessageValidator(capability, context) };
  },
};
