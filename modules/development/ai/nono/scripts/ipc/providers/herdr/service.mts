import { startJsonLinesServer, type JsonLinesServer } from "../../json-lines-server.mts";
import type { JsonLinesCapability } from "../../policy.mts";
import { getDefaultReportingCapability, type HerdrAuthority } from "./protocol.mts";
import { herdrProvider } from "./provider.mts";

/** A Herdr reporting endpoint in this process, served the same way as in the filter helper. */
export async function startReportingServer(authority: HerdrAuthority, endpoint: string, capability: JsonLinesCapability = getDefaultReportingCapability()): Promise<JsonLinesServer> {
  return startJsonLinesServer({ capability, endpoint, ...await herdrProvider.serve(authority, capability, "") });
}
