import { rmSync } from "node:fs";
import { join } from "node:path";
import { startJsonLinesServer } from "./json-lines-server.mts";
import { validateCapabilities } from "./policy.mts";
import { privateIpcDirectory } from "./private.mts";
import type { HelperArgument } from "./provider.mts";
import { providerLoaders } from "./providers/registry.mts";

// Filter helper process for one JSON-lines capability: serves a private endpoint until stdin
// closes or a termination signal arrives. ipc/helper-launch.mts starts it.

let directory: string | undefined;
let dispose: (() => Promise<void> | void) | undefined;
try {
  const { capability, home, launch }: HelperArgument = JSON.parse(process.argv[2]!);
  validateCapabilities({ version: 1, capabilities: { filter: capability }, profiles: { ordinary: {}, restricted: { filter: {} } } });
  directory = privateIpcDirectory(home, "ipc-");
  const provider = await providerLoaders[capability.provider]();
  const service = await provider.serve(launch, capability, directory);
  dispose = service.dispose;
  const endpoint = join(directory, "s");
  const server = await startJsonLinesServer({ capability, endpoint, ...service });
  let stopping: Promise<void> | undefined;
  const stop = () => stopping ??= (async () => {
    process.stdin.destroy();
    try { await server.close(); }
    finally { try { await dispose?.(); } finally { rmSync(directory!, { recursive: true, force: true }); } }
  })();
  const shutdown = () => { void stop().catch((error: Error) => { console.error(error.message); process.exitCode = 1; }); };
  process.stdin.resume();
  process.stdin.once("end", shutdown);
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
  process.stdout.write(JSON.stringify({ endpoint }) + "\n");
} catch (error) {
  try { await dispose?.(); } catch {}
  if (directory) rmSync(directory, { recursive: true, force: true });
  console.error(error instanceof Error ? error.message : "IPC filter helper failed");
  process.exitCode = 1;
}
