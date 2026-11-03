// Host-side model executor for one sandboxed Pi session. It owns provider credentials and runs
// outside nono, so its provider connections bypass the sandbox proxy and its credential routes.
import { once } from "node:events";
import { rmSync } from "node:fs";
import { createServer, type Server } from "node:net";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { privateIpcDirectory } from "../ipc/private.mts";

/** Launch arguments that model-executor/launch.mts passes as one JSON argument. */
interface ExecutorLaunch {
  packageDir: string;
  home: string;
  modelsPath?: string;
  catalogPath: string;
  credentialStore: string;
}

/** Opaque here: this process only hands the runtime from create() to serveModelExecutor(). */
declare const modelRuntimeBrand: unique symbol;
type ModelRuntime = { readonly [modelRuntimeBrand]: true };

/** The parts of the Nix-built Pi package this process loads. */
interface ModelRuntimeModule {
  ModelRuntime: { create(options: { executorSocket: null; modelsPath: string | null; modelsStorePath: string }): Promise<ModelRuntime> };
}
interface ModelExecutorModule {
  serveModelExecutor(runtime: ModelRuntime, server: Server, options: { credentialStore: string }): void;
}

let directory: string | undefined;
try {
  const { packageDir, home, modelsPath, catalogPath, credentialStore }: ExecutorLaunch = JSON.parse(process.argv[2]!);
  // Code loads only from the Nix-built Pi package, never from the writable agent directory.
  const load = (path: string) => import(pathToFileURL(join(packageDir, "dist", path)).href);
  const [{ ModelRuntime }, { serveModelExecutor }]: [ModelRuntimeModule, ModelExecutorModule] = await Promise.all([load("core/model-runtime.js"), load("core/model-executor.js")]);
  // models.json comes from the Nix store and the catalog cache from private IPC state: sandboxed
  // sessions can edit the agent directory's copies, and these decide where credentials are sent.
  const runtime = await ModelRuntime.create({ executorSocket: null, modelsPath: modelsPath ?? null, modelsStorePath: catalogPath });
  directory = privateIpcDirectory(home, "model-");
  const endpoint = join(directory, "s");
  const server = createServer();
  serveModelExecutor(runtime, server, { credentialStore });
  server.listen(endpoint);
  await once(server, "listening");
  let stopping = false;
  const stop = () => {
    if (stopping) return;
    stopping = true;
    process.stdin.destroy();
    server.close();
    rmSync(directory!, { recursive: true, force: true });
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
  // Exit now: a partly created runtime can keep the event loop alive, and the launcher would wait.
  process.exit(1);
}
