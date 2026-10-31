import { lstatSync, realpathSync } from "node:fs";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import { createMessageValidator, defaultCapabilities, selectCapabilities } from "./ipc-policy.mjs";

export interface HerdrAuthority {
  readonly upstream: string;
  readonly pane: string;
  readonly embedded: boolean;
  readonly sessionDirectory: string;
}

export interface ReportRequest {
  readonly id: string | number;
  readonly method: string;
  readonly params: Record<string, unknown>;
}

export const defaultReportingCapability = selectCapabilities(defaultCapabilities, "restricted")["herdr-reporting"];
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const sessionFile = /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}-\d{3}Z_([0-9a-f-]{36})\.jsonl$/i;

function sessionPath(value: unknown, directory: string): string {
  if (typeof value !== "string" || !isAbsolute(value) || resolve(value) !== value) throw new Error("Invalid session path");
  const match = sessionFile.exec(basename(value));
  if (!match || !uuid.test(match[1]) || realpathSync(dirname(value)) !== directory) throw new Error("Session path is outside the selected session directory");
  try {
    const entry = lstatSync(value);
    if (!entry.isFile() || entry.nlink !== 1) throw new Error("Session reference must be a regular, unaliased file");
  } catch (error) {
    // Pi allocates a reference before persisting its first message.
    if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
  }
  return join(directory, basename(value));
}

export function reportingIdentity(authority: HerdrAuthority): { source: string; agent: string } {
  return authority.embedded ? { source: "custom:neovim-pi", agent: "neovim-pi" } : { source: "herdr:pi", agent: "pi" };
}

export function reportingWorkspace(authority: HerdrAuthority): string {
  const match = /^(w[A-Za-z0-9_-]+):p[A-Za-z0-9_-]+$/.exec(authority.pane);
  if (!match) throw new Error("Invalid captured Herdr pane identity");
  return match[1];
}

export function reportingContext(authority: HerdrAuthority) {
  return {
    pane: authority.pane, workspace: reportingWorkspace(authority), ...reportingIdentity(authority), titleSource: "user:pi-session-title",
    ...(authority.embedded ? { displayAgent: "Pi", clearDisplayAgent: true } : {}),
  };
}

export function createReportValidator(authority: HerdrAuthority, capability = defaultReportingCapability) {
  const captured = structuredClone(authority);
  const validate = createMessageValidator(capability, reportingContext(captured));
  return (value: unknown): ReportRequest => {
    const request: ReportRequest = validate(value);
    const workspace = reportingWorkspace(captured);
    if (request.method === "pane.list") request.params.workspace_id = workspace;
    if (request.method === "pane.read") {
      if (typeof request.params.pane_id !== "string" || !request.params.pane_id.startsWith(workspace + ":p")) {
        throw new Error("Herdr pane read is outside the launch workspace");
      }
      request.params.lines ??= 120;
      request.params.format = "text";
      request.params.strip_ansi = true;
    }
    if (request.params.agent_session_path !== undefined) {
      request.params.agent_session_path = sessionPath(request.params.agent_session_path, captured.sessionDirectory);
    }
    return request;
  };
}

export function validateReport(value: unknown, authority: HerdrAuthority, capability = defaultReportingCapability): ReportRequest {
  return createReportValidator(authority, capability)(value);
}
