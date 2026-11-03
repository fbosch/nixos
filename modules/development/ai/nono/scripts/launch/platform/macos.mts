import * as Effect from "effect/Effect";
import { spawnSync } from "node:child_process";
import { protectedShellProfile } from "../../protection/shell.mts";
import { grant } from "../../shared/grant-plan.mts";
import type { ExitResult } from "../../shared/types.mts";
import type { Confinement } from "./confinement.mts";

/** Seatbelt: protected paths become deny rules in a generated session profile. */
export const macosConfinement: Confinement = {
  runtimeDirectoryGrants: (runtime) => [grant("--allow", runtime)],
  sharedMemoryGrants: () => [],
  runtimeSecrets: () => Effect.succeed(undefined),
  // Shell startup files and credential stores are denied in the session profile, so configuration
  // sessions keep their whole-cwd grant; only the approval store must stay outside writable grants.
  protections: ({ agent, approvals, credentialPaths }) => Effect.succeed({
    guarded: [approvals],
    splitAround: [...agent.protectedPaths, ...credentialPaths],
    splitCwd: false,
  }),
  exposedCredentials: () => [],
  runFlags: ["--trust-proxy-ca"],
  run: ({ profile, command, environment, home, protectedPaths, credentialPaths }) => Effect.gen(function* () {
    command[command.indexOf("--profile") + 1] = yield* protectedShellProfile(profile, home, environment, "darwin", protectedPaths, credentialPaths);
    return spawnSync(command[0]!, command.slice(1), { stdio: "inherit", env: environment }) as ExitResult;
  }),
};
