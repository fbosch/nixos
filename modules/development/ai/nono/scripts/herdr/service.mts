import { startJsonLinesServer, type JsonLinesServer } from "../ipc/json-lines-server.mts";
import type { JsonLinesCapability } from "../ipc/policy.mts";
import { defaultReportingCapability, type HerdrAuthority } from "./protocol.mts";
import { herdrProvider } from "./provider.mts";

/** A Herdr reporting endpoint in this process, served the same way as in the filter helper. */
export async function startReportingServer(authority: HerdrAuthority, endpoint: string, capability: JsonLinesCapability = defaultReportingCapability): Promise<JsonLinesServer> {
  return startJsonLinesServer({ capability, endpoint, ...herdrProvider.serve(authority, capability, "") });
}
