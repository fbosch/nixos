import { startJsonLinesServer, type JsonLinesServer } from "../ipc/json-lines-server.mts";
import type { JsonLinesCapability } from "../ipc/policy.mts";
import { createReportValidator, defaultReportingCapability, reportingContext, type HerdrAuthority } from "./protocol.mts";
import { createHerdrHandler } from "./reader.mts";

export async function startReportingServer(authority: HerdrAuthority, endpoint: string, capability: JsonLinesCapability = defaultReportingCapability): Promise<JsonLinesServer> {
  return startJsonLinesServer({
    capability, context: reportingContext(authority), endpoint, upstream: authority.upstream,
    validate: createReportValidator(authority, capability),
    deliver: createHerdrHandler(authority, capability),
  });
}
