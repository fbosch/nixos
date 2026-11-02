// Host-side model executor for one sandboxed Pi session. It owns provider credentials and runs
// outside nono, so its provider connections bypass the sandbox proxy and its credential routes.
import { once } from "node:events";
import { rmSync } from "node:fs";
import { createServer } from "node:net";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { privateIpcDirectory } from "./private-ipc.mjs";

let directory;
try {
  const { packageDir, home } = JSON.parse(process.argv[2]);
  // Code loads only from the Nix-built Pi package, never from the writable agent directory.
  const load = path => import(pathToFileURL(join(packageDir, "dist", path)).href);
  const [{ ModelRuntime }, { serveModelExecutor }] = await Promise.all([load("core/model-runtime.js"), load("core/model-executor.js")]);
  const runtime = await ModelRuntime.create({ executorSocket: null });
  directory = privateIpcDirectory(home, "model-");
  const endpoint = join(directory, "s");
  const server = createServer();
  serveModelExecutor(runtime, server);
  server.listen(endpoint);
  await once(server, "listening");
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    process.stdin.destroy();
    server.close();
    rmSync(directory, { recursive: true, force: true });
    // In-flight requests belong to the ended session.
    process.exit(0);
  };
  process.stdin.resume();
  process.stdin.once("end", stop);
  process.once("SIGTERM", stop);
  process.once("SIGINT", stop);
  process.stdout.write(JSON.stringify({ endpoint }) + "\n");
} catch (error) {
  if (directory) rmSync(directory, { recursive: true, force: true });
  console.error(error instanceof Error ? error.message : "Model executor failed");
  process.exitCode = 1;
}
