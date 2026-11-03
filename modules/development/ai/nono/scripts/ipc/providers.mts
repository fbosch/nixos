import { desktopProvider } from "../desktop/provider.mts";
import { herdrProvider } from "../herdr/provider.mts";
import { inheritedSocketProvider } from "./inherited-socket.mts";
import type { JsonLinesCapability } from "./policy.mts";
import type { IpcProvider } from "./provider.mts";

/** Every provider a JSON-lines capability may name; the manifest schema allows exactly these. */
export const providers: Record<JsonLinesCapability["provider"], IpcProvider> = {
  herdr: herdrProvider,
  desktop: desktopProvider,
  "inherited-socket": inheritedSocketProvider,
};
