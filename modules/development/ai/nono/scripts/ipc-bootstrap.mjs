import { spawn } from "node:child_process";
import { once } from "node:events";
import { realpathSync, statSync } from "node:fs";
import { join, sep } from "node:path";
import { fileURLToPath } from "node:url";

export async function withFilterHelper(environment, home, capability, launch, run) {
  const helper = spawn(process.execPath, [fileURLToPath(new URL("./json-lines-helper.mjs", import.meta.url)), JSON.stringify({ capability, home, ...launch })], {
    env: {}, stdio: ["pipe", "pipe", "pipe"],
  });
  const exited = once(helper, "exit");
  let startupError = "";
  helper.stderr.on("data", chunk => { startupError = (startupError + chunk.toString()).slice(-2048); });
  let timer;
  try {
    const endpoint = await new Promise((resolve, reject) => {
      let input = "";
      timer = setTimeout(() => reject(new Error("IPC filter helper startup timed out")), 5000);
      helper.once("error", reject);
      helper.once("exit", () => reject(new Error(`IPC filter helper exited before readiness: ${startupError}`)));
      helper.stdout.on("data", chunk => {
        input += chunk.toString();
        if (input.length > 4096) return reject(new Error("Invalid IPC helper readiness frame"));
        if (!input.includes("\n")) return;
        try {
          const ready = JSON.parse(input);
          const base = join(realpathSync(home), ".pi-ipc") + sep;
          if (typeof ready.endpoint !== "string" || !ready.endpoint.startsWith(base) || !statSync(ready.endpoint).isSocket()) throw new Error("Invalid IPC helper endpoint");
          clearTimeout(timer);
          resolve(ready.endpoint);
        } catch (error) { reject(error); }
      });
    });
    return await run({ ...environment, [capability.socketEnvironment]: endpoint });
  } finally {
    clearTimeout(timer);
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
