import { join } from "node:path";
import { createMessageValidator } from "../ipc/policy.mts";
import type { IpcProvider } from "../ipc/provider.mts";
import { createDesktopHandler, desktopAuthority, type DesktopAuthority } from "./broker.mts";
import * as Effect from "effect/Effect";

/**
 * Clipboard, screenshots and image viewing on the host desktop. The helper runs fixed tools with
 * only the inherited compositor connection, so Pi never reaches the compositor or session bus.
 */
export const desktopProvider: IpcProvider = {
  start: (environment, { inherited, startHelper }, capability) => {
    const bound = { ...environment };
    delete bound[capability.socketEnvironment];
    const authority = desktopAuthority(inherited);
    if (!authority) return Effect.succeed(bound);
    return startHelper(bound, capability, authority);
  },
  serve: (launch, capability, directory) => {
    const handler = createDesktopHandler(launch as DesktopAuthority, capability.limits.upstreamTimeoutMs, join(directory, "images"));
    return { context: {}, validate: createMessageValidator(capability, {}), deliver: handler, dispose: () => handler.close() };
  },
};
