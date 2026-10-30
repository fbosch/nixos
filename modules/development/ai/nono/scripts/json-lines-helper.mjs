import { rmSync } from "node:fs";
import { join } from "node:path";
import { privateIpcDirectory } from "./private-ipc.mjs";
import { createMessageValidator, validateCapabilities } from "./ipc-policy.mjs";
import { startJsonLinesServer } from "./json-lines-server.mjs";

let directory;
try {
  const { capability, home, authority, upstream, context } = JSON.parse(process.argv[2]);
  validateCapabilities({ version: 1, capabilities: { filter: capability }, profiles: { ordinary: {}, restricted: { filter: {} } } });
  let validate;
  let capturedContext = context;
  let capturedUpstream = upstream;
  if (capability.provider === "herdr") {
    const { createReportValidator, reportingContext } = await import("./herdr-protocol.mts");
    capturedContext = reportingContext(authority);
    capturedUpstream = authority.upstream;
    validate = createReportValidator(authority, capability);
  } else {
    validate = createMessageValidator(capability, capturedContext);
  }
  directory = privateIpcDirectory(home, "ipc-");
  const endpoint = join(directory, "s");
  const server = await startJsonLinesServer({ capability, context: capturedContext, endpoint, upstream: capturedUpstream, validate });
  let stopping;
  const stop = () => stopping ??= (async () => {
    process.stdin.destroy();
    await server.close();
    rmSync(directory, { recursive: true, force: true });
  })();
  const shutdown = () => { void stop().catch(error => { console.error(error.message); process.exitCode = 1; }); };
  process.stdin.resume();
  process.stdin.once("end", shutdown);
  process.once("SIGTERM", shutdown);
  process.once("SIGINT", shutdown);
  process.stdout.write(JSON.stringify({ endpoint }) + "\n");
} catch (error) {
  if (directory) rmSync(directory, { recursive: true, force: true });
  console.error(error instanceof Error ? error.message : "IPC filter helper failed");
  process.exitCode = 1;
}
