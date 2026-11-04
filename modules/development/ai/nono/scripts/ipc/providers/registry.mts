import type { JsonLinesCapability } from "../policy.mts";
import type { IpcProvider } from "../provider.mts";

/** Load only the helper's selected provider; the manifest schema allows exactly these names. */
export const providerLoaders: Record<JsonLinesCapability["provider"], () => Promise<IpcProvider>> = {
  herdr: async () => (await import("./herdr/provider.mts")).herdrProvider,
  desktop: async () => (await import("./desktop/provider.mts")).desktopProvider,
  neovim: async () => (await import("./neovim/provider.mts")).neovimProvider,
  "inherited-socket": async () => (await import("./inherited-socket.mts")).inheritedSocketProvider,
};
