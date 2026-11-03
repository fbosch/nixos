import { realpathSync, statSync } from "node:fs";
import { isAbsolute } from "node:path";
import type { Environment, SessionStep } from "../shared/types.mts";
import { selectCapabilities, type CapabilityRegistry, type JsonLinesCapability } from "./policy.mts";
import { withFilterHelper } from "./helper-launch.mts";
import { withHerdrReporter } from "../herdr/bootstrap.mts";
import { withDesktopBroker } from "../desktop/bootstrap.mts";

function withInheritedSocket<T>(environment: Environment, inherited: Environment, home: string, cwd: string, capability: JsonLinesCapability, run: SessionStep<T>): T | Promise<T> {
  const bound = { ...environment };
  delete bound[capability.socketEnvironment];
  const upstream = inherited[capability.socketEnvironment];
  if (!upstream) return run(bound);
  if (!isAbsolute(upstream) || !statSync(upstream).isSocket()) throw new Error(`Inherited IPC endpoint must be an existing absolute Unix socket: ${capability.socketEnvironment}`);
  return withFilterHelper(bound, home, capability, {
    upstream: realpathSync(upstream), context: { cwd: realpathSync(cwd), home: realpathSync(home), uid: process.getuid!() },
  }, run);
}

/** Starts a filter helper for every JSON-lines capability of `profile`, then runs the session. */
export async function withIpcCapabilities<T>(environment: Environment, inherited: Environment, home: string, cwd: string, agentDir: string, args: readonly string[], registry: CapabilityRegistry, profile: "ordinary" | "restricted", run: SessionStep<T>): Promise<T> {
  const selected = Object.values(selectCapabilities(registry, profile)).filter((capability): capability is JsonLinesCapability & { backend: "json-lines" } => capability.backend === "json-lines");
  const activeVariables = new Set(selected.map(capability => capability.socketEnvironment));
  const bound = { ...environment };
  if (profile === "restricted") {
    for (const capability of Object.values(registry.capabilities)) {
      if (capability.backend === "json-lines" && !activeVariables.has(capability.socketEnvironment)) delete bound[capability.socketEnvironment];
    }
  }
  const next = (index: number, current: Environment): T | Promise<T> => {
    if (index === selected.length) return run(current);
    const capability = selected[index]!;
    const proceed = (updated: Environment) => next(index + 1, updated);
    if (capability.provider === "herdr") return withHerdrReporter(current, inherited, home, cwd, agentDir, args, proceed, capability);
    if (capability.provider === "desktop") return withDesktopBroker(current, inherited, home, capability, proceed);
    return withInheritedSocket(current, inherited, home, cwd, capability, proceed);
  };
  if (profile === "restricted" && !selected.some(capability => capability.provider === "herdr")) {
    return withHerdrReporter(bound, inherited, home, cwd, agentDir, args, updated => next(0, updated), null);
  }
  return next(0, bound);
}
