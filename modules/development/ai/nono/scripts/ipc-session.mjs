import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import { selectCapabilities } from "./ipc-policy.mjs";
import { withFilterHelper } from "./ipc-bootstrap.mjs";
import { withHerdrReporter } from "./herdr-bootstrap.mjs";

function withInheritedSocket(environment, inherited, home, cwd, capability, run) {
  const bound = { ...environment };
  delete bound[capability.socketEnvironment];
  const upstream = inherited[capability.socketEnvironment];
  if (!upstream) return run(bound);
  if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) throw new Error(`Inherited IPC endpoint must be an existing absolute Unix socket: ${capability.socketEnvironment}`);
  return withFilterHelper(bound, home, capability, {
    upstream: realpathSync(upstream), context: { cwd: realpathSync(cwd), home: realpathSync(home), uid: process.getuid() },
  }, run);
}

export async function withIpcCapabilities(environment, inherited, home, cwd, agentDir, args, registry, profile, run) {
  const selected = Object.values(selectCapabilities(registry, profile)).filter(capability => capability.backend === "json-lines");
  const activeVariables = new Set(selected.map(capability => capability.socketEnvironment));
  const bound = { ...environment };
  if (profile === "restricted") {
    for (const capability of Object.values(registry.capabilities)) {
      if (capability.backend === "json-lines" && !activeVariables.has(capability.socketEnvironment)) delete bound[capability.socketEnvironment];
    }
  }
  const next = (index, current) => {
    if (index === selected.length) return run(current);
    const capability = selected[index];
    const proceed = updated => next(index + 1, updated);
    return capability.provider === "herdr"
      ? withHerdrReporter(current, inherited, home, cwd, agentDir, args, proceed, capability)
      : withInheritedSocket(current, inherited, home, cwd, capability, proceed);
  };
  if (profile === "restricted" && !selected.some(capability => capability.provider === "herdr")) {
    return withHerdrReporter(bound, inherited, home, cwd, agentDir, args, updated => next(0, updated), null);
  }
  return next(0, bound);
}
