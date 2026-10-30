import { startJsonLinesServer } from "./json-lines-server.mjs";
import { createReportValidator, defaultReportingCapability, reportingContext, type HerdrAuthority } from "./herdr-protocol.mts";

export async function startReportingServer(authority: HerdrAuthority, endpoint: string, capability = defaultReportingCapability) {
  return startJsonLinesServer({
    capability, context: reportingContext(authority), endpoint, upstream: authority.upstream,
    validate: createReportValidator(authority, capability),
  });
}
