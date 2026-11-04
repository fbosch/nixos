import type * as Effect from "effect/Effect";
import type * as Scope from "effect/Scope";
import type { HostProcessError, SandboxError } from "../shared/errors.mts";
import type { Environment } from "../shared/types.mts";
import type { ConnectionDeliver, IpcConnection } from "./json-lines-server.mts";
import type { JsonLinesCapability, LaunchContext, MessageValidator } from "./policy.mts";

// An IPC provider owns both sides of one JSON-lines capability: `start` runs in the launcher and
// decides whether a filter helper is needed; `serve` runs inside that helper process.

/** What the launcher knows about the session when a provider starts. */
export interface ProviderSession {
  /** The environment the launcher started with; providers read host endpoints from it. */
  inherited: Environment;
  home: string;
  cwd: string;
  agentDir: string;
  /** Pi's command-line arguments. */
  args: readonly string[];
  /**
   * Starts the filter helper for `capability`; `launch` must be JSON-serializable and reaches the
   * provider's `serve`. Injected so providers do not depend on the helper process that loads them.
   */
  startHelper(environment: Environment, capability: JsonLinesCapability, launch: unknown): Effect.Effect<Environment, HostProcessError, Scope.Scope>;
}

/** What the helper's JSON-lines server needs from a provider. */
export interface HelperService {
  context: LaunchContext;
  /** Socket to forward validated requests to, when `deliver` is absent. */
  upstream?: string;
  validate: MessageValidator;
  deliver?: ConnectionDeliver;
  disconnect?: (connection: IpcConnection) => Promise<void> | void;
  /** Releases provider state when the helper stops. */
  dispose?: () => Promise<void> | void;
}

export interface IpcProvider {
  /**
   * Bind the capability for this session, usually by starting a filter helper with `session.startHelper`
   * and launch data that `serve` reads back. Returns the session environment.
   */
  start(environment: Environment, session: ProviderSession, capability: JsonLinesCapability): Effect.Effect<Environment, HostProcessError | SandboxError, Scope.Scope>;
  /** Inside the helper process: `launch` is what `start` passed to `startHelper`. `directory` is private to the helper. */
  serve(launch: unknown, capability: JsonLinesCapability, directory: string): HelperService;
  /** Restricted profile only: remove this provider's inherited variables when no capability selects it. */
  scrub?(environment: Environment): Environment;
}

/** The helper process's single argument; ipc/helper-launch.mts serializes it. */
export interface HelperArgument {
  capability: JsonLinesCapability;
  home: string;
  launch: unknown;
}
