import { rmSync } from "node:fs";
import { join } from "node:path";
import { privateIpcDirectory } from "./private.mts";
import { createMessageValidator, validateCapabilities } from "./policy.mts";
import { startJsonLinesServer, type Deliver } from "./json-lines-server.mts";
import type { DesktopAuthority, DesktopHandler } from "../desktop/broker.mts";
import type { HerdrAuthority } from "../herdr/protocol.mts";
import type { JsonLinesCapability, LaunchContext, MessageValidator } from "./policy.mts";

/** Provider-specific launch data, serialized into the helper's single argument. */
export interface HelperLaunch {
  authority?: HerdrAuthority;
  desktop?: DesktopAuthority;
  upstream?: string;
  context?: LaunchContext;
}

/** The complete helper argument; ipc/helper-launch.mts serializes it. */
export interface HelperArgument extends HelperLaunch {
  capability: JsonLinesCapability;
  home: string;
}


let directory: string | undefined;
let dispose: (() => void) | undefined;
try {
  const { capability, home, authority, upstream, context, desktop }: HelperArgument = JSON.parse(process.argv[2]!);
  validateCapabilities({ version: 1, capabilities: { filter: capability }, profiles: { ordinary: {}, restricted: { filter: {} } } });
  let validate: MessageValidator;
  let capturedContext: LaunchContext = context!;
  let capturedUpstream = upstream;
  let deliver: Deliver | undefined;
  directory = privateIpcDirectory(home, "ipc-");
  if (capability.provider === "herdr") {
    const { createReportValidator, reportingContext } = await import("../herdr/protocol.mts");
    capturedContext = reportingContext(authority!);
    capturedUpstream = authority!.upstream;
    validate = createReportValidator(authority!, capability);
    const { createHerdrHandler } = await import("../herdr/reader.mts");
    deliver = createHerdrHandler(authority!, capability);
  } else if (capability.provider === "desktop") {
    const { createDesktopHandler } = await import("../desktop/broker.mts");
    capturedContext = {};
    validate = createMessageValidator(capability, capturedContext);
    deliver = createDesktopHandler(desktop!, capability.limits.upstreamTimeoutMs, join(directory, "images"));
    dispose = () => (deliver as DesktopHandler).close();
  } else {
    validate = createMessageValidator(capability, capturedContext);
  }
  const endpoint = join(directory, "s");
  const server = await startJsonLinesServer({ capability, context: capturedContext, endpoint, upstream: capturedUpstream, validate, deliver });
  let stopping: Promise<void> | undefined;
  const stop = () => stopping ??= (async () => {
    process.stdin.destroy();
    try { await server.close(); }
    finally { dispose?.(); rmSync(directory!, { recursive: true, force: true }); }
  })();
  const shutdown = () => { void stop().catch((error: Error) => { console.error(error.message); process.exitCode = 1; }); };
  process.stdin.resume();
  process.stdin.once("end", shutdown);
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
  process.stdout.write(JSON.stringify({ endpoint }) + "\n");
} catch (error) {
  dispose?.();
  if (directory) rmSync(directory, { recursive: true, force: true });
  console.error(error instanceof Error ? error.message : "IPC filter helper failed");
  process.exitCode = 1;
}
