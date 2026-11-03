import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { AgentProtection } from "../../protection/agent.mts";
import type { HostProcessError, SandboxError } from "../../shared/errors.mts";
import type { Grant } from "../../shared/grant-plan.mts";
import type { Environment, ExitResult, NonoProfile } from "../../shared/types.mts";

// How one kernel mechanism enforces the shared launch policy. Landlock (Linux) cannot subtract a
// protected child from a writable grant, so it keeps protected paths outside every writable grant.
// Seatbelt (macOS) adds deny rules to a generated profile instead. Grant planning is shared; each
// platform answers only the questions below.

export interface ProtectionInput {
  home: string;
  environment: Environment;
  agent: AgentProtection;
  /** Directory of the host-only reference approval store. */
  approvals: string;
  /** Credential stores the host model executor owns; empty without the executor. */
  credentialPaths: readonly string[];
}

export interface Protections {
  /** No writable grant may contain or lie inside these paths; the launch fails otherwise. */
  guarded: string[];
  /** Writable grants that overlap these paths are split into their unprotected entries. */
  splitAround: string[];
  /** Split the working directory too when it overlaps `splitAround`, instead of nono's whole-directory grant. */
  splitCwd: boolean;
}

export interface RunInput {
  nono: string;
  /** The Nix-pinned profile path and its snapshot. */
  profile: string;
  nonoProfile: NonoProfile;
  command: string[];
  environment: Environment;
  home: string;
  protectedPaths: readonly string[];
  credentialPaths: readonly string[];
}

export interface Confinement {
  /** Grants for the inherited runtime directory in the ordinary IPC profile. */
  runtimeDirectoryGrants(runtime: string): Grant[];
  /** Grants every session needs for shared memory. */
  sharedMemoryGrants(): Grant[];
  /** Runtime-directory secrets no grant may reach, or undefined when there is nothing to guard. */
  runtimeSecrets(environment: Environment): Effect.Effect<string[] | undefined, SandboxError>;
  protections(input: ProtectionInput): Effect.Effect<Protections, SandboxError>;
  /** Credential files readable despite executor mode, reported as a warning. */
  exposedCredentials(agentDirectories: readonly string[]): string[];
  /** Flags `nono run` needs on this platform, after the cwd and save-prompt flags. */
  runFlags: readonly string[];
  /** Run the planned nono command and report how it exited. */
  run(input: RunInput): Effect.Effect<ExitResult, SandboxError | HostProcessError, Scope.Scope>;
}
