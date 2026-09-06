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

function renderHostContext(hostName: string, metadata?: unknown): string {
  const context = [`- Runtime hostname: \`${hostName}\``];

  if (!isRecord(metadata)) {
    context.push(
      `- No matching \`flake.meta.hosts.${hostName}\` metadata was found.`,
    );
    return context.join("\n");
  }

  const exposedMetadata = Object.fromEntries(
    Object.entries(metadata).filter(([key]) => exposedMetadataFields.has(key)),
  );

  context.push(
    `- \`flake.meta.hosts.${hostName}\`:\n\n\`\`\`json\n${JSON.stringify(
      exposedMetadata,
      null,
      2,
    )}\n\`\`\``,
  );

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
        currentHostContext = `${renderHostContext(hostName)}\n- Flake metadata lookup failed with exit code ${result.code}.`;
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
      currentHostContext = `${renderHostContext(hostName)}\n- Flake metadata lookup could not be run.`;
      if (ctx.hasUI) {
        ctx.ui.notify(
          "Flake host metadata lookup could not be run; only the hostname was injected.",
          "warning",
        );
      }
    }
  });

  pi.on("before_agent_start", (event) => ({
    systemPrompt: `${event.systemPrompt}\n\n## Current host context\n${currentHostContext}`,
  }));
}
