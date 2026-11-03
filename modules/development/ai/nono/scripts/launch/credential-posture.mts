import * as Effect from "effect/Effect";
import { join } from "node:path";
import { assertCredentialGrants } from "../credentials/grants.mts";
import { credentialStoreDirectory } from "../credentials/store.mts";
import { agentCredentialPaths, type AgentProtection } from "../protection/agent.mts";
import { attempt, type SandboxError } from "../shared/errors.mts";
import { grant, type Grant, type GrantPlan } from "../shared/grant-plan.mts";
import { existingDirectory, existingFile, within } from "../shared/paths.mts";
import type { Environment, NonoProfile } from "../shared/types.mts";
import { MODEL_EXECUTOR_SOCKET } from "../model-executor/launch.mts";

/**
 * Who owns Pi's credential files in this session. In `executor` mode the host model executor holds
 * them and no sandbox grant may reach them. In `sandbox` mode (PI_MODEL_EXECUTOR=0) Pi reads and
 * refreshes its own login, so it receives narrow write grants to the migrated store.
 */
export type CredentialPosture =
  | { mode: "executor"; hostOnly: string[] }
  | { mode: "sandbox"; files: Grant[]; directories: string[] };

/**
 * The launcher sets the executor socket only when it started the executor for this session.
 * An executor session with no credential store or agent directory falls back to sandbox mode.
 */
export function credentialPosture(home: string, agentDir: string, environment: Environment, agent: AgentProtection): Effect.Effect<CredentialPosture, SandboxError> {
  return Effect.gen(function* () {
    const hostOnly = environment[MODEL_EXECUTOR_SOCKET] ? yield* agentCredentialPaths(home, agentDir) : [];
    if (hostOnly.length > 0) return { mode: "executor" as const, hostOnly };
    return yield* sandboxCredentials(home, agent);
  });
}

function sandboxCredentials(home: string, agent: AgentProtection): Effect.Effect<CredentialPosture, SandboxError> {
  return attempt(() => {
    const files = agent.authFiles.map((path) => grant("--allow-file", path));
    const directories: string[] = [];
    let store: string | undefined;
    try { store = existingDirectory(credentialStoreDirectory(home)); } catch { store = undefined; }
    if (store !== undefined) {
      const auth = join(store, "auth.json");
      if (existingFile(auth)) files.push(grant("--allow-file", auth));
      const profiles = existingDirectory(join(store, "auth-profiles"));
      if (profiles !== undefined) directories.push(profiles);
    }
    return { mode: "sandbox" as const, files, directories };
  });
}

/** Credential stores no grant may reach: the executor's, or none. */
export function hostOnlyCredentials(posture: CredentialPosture): string[] {
  return posture.mode === "executor" ? posture.hostOnly : [];
}

/** Whether an agent runtime path may stay writable; executor-owned credential stores may not. */
export function writableRuntimePath(posture: CredentialPosture, path: string): boolean {
  return !hostOnlyCredentials(posture).some((credential) => within(path, credential));
}

/** Executor mode: no grant, including profile reads, may reach the credential store. */
export function assertCredentialPosture(posture: CredentialPosture, plan: GrantPlan, cwd: string, home: string, environment: Environment, profile: NonoProfile): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    if (posture.mode !== "executor") return;
    if ((yield* attempt(() => existingDirectory(home))) === undefined) return;
    yield* assertCredentialGrants(plan, cwd, home, environment, profile, [credentialStoreDirectory(home)], "Pi");
  });
}
