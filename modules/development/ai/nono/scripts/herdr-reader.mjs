import { stripVTControlCharacters } from "node:util";
import { requestJsonLine } from "./json-lines-server.mjs";
import { reportingWorkspace } from "./herdr-protocol.mts";

const reportingMethods = new Set(["pane.report_agent", "pane.report_agent_session", "pane.report_metadata", "pane.release_agent"]);
const paneId = /^w[A-Za-z0-9_-]+:p[A-Za-z0-9_-]+$/;
const tabId = /^w[A-Za-z0-9_-]+:t[A-Za-z0-9_-]+$/;

function object(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid Herdr response object");
  return value;
}

function text(value, maxBytes = 4096) {
  if (typeof value !== "string" || !value.isWellFormed() || Buffer.byteLength(value) > maxBytes) throw new Error("Invalid Herdr response text");
  return stripVTControlCharacters(value).replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f]/gu, "");
}

function scope(value, workspace) {
  const pane = object(value);
  if (pane.workspace_id !== workspace || !paneId.test(pane.pane_id) || !pane.pane_id.startsWith(workspace + ":p") ||
      !tabId.test(pane.tab_id) || !pane.tab_id.startsWith(workspace + ":t") || !Number.isSafeInteger(pane.revision) || pane.revision < 0) {
    throw new Error("Herdr response is outside the launch workspace or malformed");
  }
  return { pane_id: pane.pane_id, workspace_id: workspace, tab_id: pane.tab_id, revision: pane.revision };
}

function paneInfo(value, workspace) {
  const pane = object(value);
  const info = scope(pane, workspace);
  if (typeof pane.focused !== "boolean" || !["unknown", "idle", "working", "blocked", "done"].includes(pane.agent_status)) {
    throw new Error("Invalid Herdr pane status");
  }
  Object.assign(info, { terminal_id: text(pane.terminal_id, 192), focused: pane.focused, agent_status: pane.agent_status });
  for (const field of ["agent", "cwd", "label", "terminal_title_stripped"]) {
    if (pane[field] !== undefined) info[field] = pane[field] === null ? null : text(pane[field]);
  }
  return info;
}

export function createHerdrHandler(authority, capability) {
  const captured = structuredClone(authority);
  const workspace = reportingWorkspace(captured);
  return async request => {
    const handshake = request.method === "ping";
    const listing = request.method === "pane.list";
    const reading = request.method === "pane.read";
    if (!handshake && !listing && !reading && !reportingMethods.has(request.method)) throw new Error("Unsupported Herdr operation");
    const response = await requestJsonLine(captured.upstream, { ...request, id: String(request.id) }, capability.limits);
    if (!handshake && !listing && !reading) {
      if (response.ok !== true) throw new Error("Herdr rejected the report");
      return;
    }
    if (response.id !== String(request.id) || response.error !== undefined) throw new Error("Herdr read response was rejected or mismatched");
    const result = object(response.result);
    let projected;
    if (handshake) {
      if (result.type !== "pong" || !Number.isSafeInteger(result.protocol) || result.protocol < 0) throw new Error("Invalid Herdr handshake");
      projected = { type: "pong", version: text(result.version, 128), protocol: result.protocol };
    } else if (listing) {
      if (result.type !== "pane_list" || !Array.isArray(result.panes) || result.panes.length > 128) throw new Error("Invalid Herdr pane list");
      projected = { type: "pane_list", panes: result.panes.map(pane => paneInfo(pane, workspace)) };
    } else {
      if (result.type !== "pane_read") throw new Error("Invalid Herdr pane read");
      const read = object(result.read);
      const identity = scope(read, workspace);
      if (read.pane_id !== request.params.pane_id || read.source !== request.params.source || read.format !== "text" || typeof read.truncated !== "boolean") {
        throw new Error("Herdr read response does not match the request");
      }
      const content = text(read.text, capability.limits.maxFrameBytes);
      const lineCount = content.split("\n").length - Number(content.endsWith("\n"));
      if (lineCount > request.params.lines) throw new Error("Herdr read response exceeds the line limit");
      projected = { type: "pane_read", read: { ...identity, source: read.source, format: "text", text: content, truncated: read.truncated } };
    }
    if (Buffer.byteLength(JSON.stringify({ id: request.id, ok: true, result: projected })) + 1 > capability.limits.maxFrameBytes) throw new Error("Herdr read response exceeds the output limit");
    return projected;
  };
}
