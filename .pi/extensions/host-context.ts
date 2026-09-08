/// <reference path="../types.d.ts" />

import { hostname } from "node:os";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const exposedMetadataFields = new Set([
  "role",
  "sshAlias",
  "sshAgent",
  "tailscale",
  "local",
  "primaryUser",
  "useTailnet",
  "corporate",
  "nixDistribution",
  "system",
  "hardware",
]);

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function escapeXml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

function renderXmlElement(name: string, value: unknown, indent = "  "): string {
  if (value === null || value === undefined) {
    return `${indent}<${name} />`;
  }

  if (Array.isArray(value)) {
    return value.map((item) => renderXmlElement(name, item, indent)).join("\n");
  }

  if (isRecord(value)) {
    const children = Object.entries(value)
      .map(([key, child]) => renderXmlElement(key, child, `${indent}  `))
      .join("\n");

    return `${indent}<${name}>\n${children}\n${indent}</${name}>`;
  }

  return `${indent}<${name}>${escapeXml(String(value))}</${name}>`;
}

function renderHostContext(
  hostName: string,
  metadata?: unknown,
  error?: string,
): string {
  const hostMetadataPath = `flake.meta.hosts.${hostName}`;
  const context = [
    "<host_context>",
    renderXmlElement("runtime_hostname", hostName),
  ];

  if (isRecord(metadata)) {
    const exposedMetadata = Object.fromEntries(
      Object.entries(metadata).filter(([key]) =>
        exposedMetadataFields.has(key),
      ),
    );

    context.push(
      `  <host_metadata path="${escapeXml(hostMetadataPath)}">`,
      ...Object.entries(exposedMetadata).map(([key, value]) =>
        renderXmlElement(key, value),
      ),
      "  </host_metadata>",
    );
  } else {
    context.push(
      `  <host_metadata path="${escapeXml(hostMetadataPath)}" />`,
      `  <error>No matching ${escapeXml(hostMetadataPath)} metadata was found.</error>`,
    );
  }

  if (error) {
    context.push(`  <error>${escapeXml(error)}</error>`);
  }

  context.push("</host_context>");
  return context.join("\n");
}

export default function hostContext(pi: ExtensionAPI) {
  const hostName = hostname();
  let currentHostContext = renderHostContext(hostName);

  pi.on("session_start", async (_event, ctx) => {
    try {
      const result = await pi.exec(
        "nix",
        ["eval", "--json", `git+file://${ctx.cwd}#meta.hosts`],
        { timeout: 5000 },
      );

      if (result.code !== 0) {
        currentHostContext = renderHostContext(
          hostName,
          undefined,
          `Flake metadata lookup failed with exit code ${result.code}.`,
        );
        if (ctx.hasUI) {
          ctx.ui.notify(
            "Flake host metadata lookup failed; only the hostname was injected.",
            "warning",
          );
        }
        return;
      }

      const hosts: unknown = JSON.parse(result.stdout);
      const metadata = isRecord(hosts) ? hosts[hostName] : undefined;
      currentHostContext = renderHostContext(hostName, metadata);

      if (!metadata && ctx.hasUI) {
        ctx.ui.notify(
          `No flake host metadata matches runtime hostname ${hostName}.`,
          "warning",
        );
      }
    } catch {
      currentHostContext = renderHostContext(
        hostName,
        undefined,
        "Flake metadata lookup could not be run.",
      );
      if (ctx.hasUI) {
        ctx.ui.notify(
          "Flake host metadata lookup could not be run; only the hostname was injected.",
          "warning",
        );
      }
    }
  });

  pi.on("before_agent_start", (event) => ({
    systemPrompt: `${event.systemPrompt}\n${currentHostContext}`,
  }));
}
