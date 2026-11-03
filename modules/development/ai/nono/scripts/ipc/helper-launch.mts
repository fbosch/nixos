import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import type { Environment, SessionStep } from "../shared/types.mts";
import type { HelperArgument, HelperLaunch } from "./helper.mts";
import type { JsonLinesCapability } from "./policy.mts";
import { helperEndpoint } from "./private.mts";

export async function withFilterHelper<T>(environment: Environment, home: string, capability: JsonLinesCapability, launch: HelperLaunch, run: SessionStep<T>): Promise<T> {
  const helper = spawn(process.execPath, [fileURLToPath(new URL("./helper.mts", import.meta.url)), JSON.stringify({ capability, home, ...launch } satisfies HelperArgument)], {
    env: {}, stdio: ["pipe", "pipe", "pipe"],
  });
  const exited = once(helper, "exit");
  let startupError = "";
  helper.stderr.on("data", (chunk: Buffer) => { startupError = (startupError + chunk.toString()).slice(-2048); });
  try {
    const endpoint = await helperEndpoint(helper, home, { name: "IPC filter helper", timeoutMs: 5000, diagnostics: () => startupError });
    return await run({ ...environment, [capability.socketEnvironment]: endpoint });
  } finally {
    helper.stdin.end();
    // Accepted deliveries and cleanup each get their configured upstream deadline.
    const grace = 2 * capability.limits.upstreamTimeoutMs + 1000;
    const timeout = setTimeout(() => helper.kill("SIGTERM"), grace);
    const hardTimeout = setTimeout(() => helper.kill("SIGKILL"), grace + 2000);
    await exited;
    clearTimeout(timeout);
    clearTimeout(hardTimeout);
  }
}
