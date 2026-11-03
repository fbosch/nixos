import * as Effect from "effect/Effect";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, isAbsolute } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { credentialEnvironmentForDirenv } from "./credentials/definitions.mts";
import { credentialProxySession } from "./credentials/proxy.mts";
import { credentialFilesOutsideStore, migrateCredentialStore, runningSandboxes } from "./credentials/store.mts";
import { loadCapabilities } from "./ipc/policy.mts";
import { ipcCapabilities, providerSession } from "./ipc/session.mts";
import { sessionServices } from "./ipc/services.mts";
import { nonoDiagnostics } from "./launch/diagnostics.mts";
import { configurePiPaths, loadProjectEnvironment, sessionEnvironment } from "./launch/environment.mts";
import { planLaunchCommand } from "./launch/plan.mts";
import { prepareJitiCache, prepareNpmCache, prepareRuntimeLocks, prepareSandboxRuntime } from "./launch/runtime.mts";
import { ensureSshIdentity } from "./launch/ssh.mts";
import { MODEL_EXECUTOR_SOCKET, modelExecutorEnabled, modelExecutor, modelExecutorEnvironment } from "./model-executor/launch.mts";
import { prepareAgentRuntime } from "./protection/agent.mts";
import { protectedShellProfile } from "./protection/shell.mts";
import { type HostProcessError, type SandboxError, attempt } from "./shared/errors.mts";
import type { Environment, ExitResult } from "./shared/types.mts";
import { readNonoProfile } from "./shared/nono-profile.mts";

// Entry point of the packaged `pi` wrapper: node launcher.mts <nono> <raw-pi> <profile> <direnv> <env> [pi args...]

// process.execve replaces this process on success; @types/node declares it as returning void.
function execRawPi(rawPi: string, piArgs: string[]): void {
  if (!isAbsolute(rawPi) || !existsSync(rawPi)) throw new Error(`Raw Pi executable missing: ${rawPi}`);
  // Explicit raw mode replaces this process before any sandbox policy, proxy, IPC, or configuration checks.
  // Kernel restrictions inherited from a parent sandbox still apply.
  const environment: Environment = { ...process.env };
  environment.PI_NONO_MODE = "disabled";
  // Raw mode resolves credentials itself; an inherited executor socket belongs to another session.
  delete environment[MODEL_EXECUTOR_SOCKET];
  configurePiPaths(environment, homedir(), (environment.PATH || "").split(delimiter)[0]);
  process.execve!(rawPi, [rawPi, ...piArgs], environment);
}

function launchSandboxed(nono: string, rawPi: string, profile: string, direnv: string, envBinary: string, args: string[]): Effect.Effect<ExitResult, SandboxError | HostProcessError> {
  return Effect.gen(function* () {
    // Capture the binary wrapper's manifest before mutable project environment loading.
    const registry = loadCapabilities(process.env.PI_IPC_MANIFEST || undefined);
    let environment: Environment = { ...process.env };
    // No mutable JS preload or module path may run in this pre-sandbox process.
    delete environment.NODE_OPTIONS;
    delete environment.NODE_PATH;
    const entryBin = (environment.PATH || "").split(delimiter)[0];
    const home = homedir();
    const inheritedEnvironment = { ...environment };
    // The binary wrapper pins this store path; project environment loading cannot replace it.
    const sshAdd = environment.PI_SSH_ADD;
    const safeEnvironment = credentialEnvironmentForDirenv(environment);
    try {
      environment = loadProjectEnvironment(process.cwd(), safeEnvironment, direnv);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`pi sandbox launch: ${message}; continuing without project direnv environment`);
      environment = safeEnvironment;
    }
    environment = sessionEnvironment(inheritedEnvironment, environment, home);
    const agentDir = configurePiPaths(environment, home, entryBin);
    // Confined sessions share locks outside read-only configuration.
    environment.PI_LOCKFILE_DIR = prepareRuntimeLocks(home);
    prepareSandboxRuntime(home);
    prepareAgentRuntime(agentDir);
    // Existing setups move to the credential store on the first sandboxed launch while no other
    // sandboxed session is running.
    try {
      if (credentialFilesOutsideStore([realpathSync(agentDir)]).length > 0) {
        const running = runningSandboxes();
        if (running === undefined) {
          console.warn("pi sandbox launch: cannot list running sandboxes; credentials move to the Pi credential store on a later launch.");
        } else if (running.length > 0) {
          console.warn(`pi sandbox launch: ${running.length} other sandboxed Pi session(s) are running; credentials move to the Pi credential store on the first launch after they exit.`);
        } else {
          for (const warning of migrateCredentialStore(home, agentDir).warnings) console.warn(`pi sandbox launch: ${warning}`);
        }
      }
    } catch (error) {
      console.warn(`pi sandbox launch: could not move credentials to the Pi credential store (${error instanceof Error ? error.message : String(error)}); continuing with the existing files.`);
    }
    ensureSshIdentity(environment, home, sshAdd);
    // The Nix-pinned profile is immutable for the whole launch; parse it once.
    const nonoProfile = yield* attempt(() => readNonoProfile(profile));
    const ipcRestricted = nonoProfile.linux?.af_unix_mediation === "pathname";
    const runPi = (boundEnvironment: Environment) => Effect.gen(function* () {
      environment = yield* nonoDiagnostics(boundEnvironment);
      environment.PI_NONO_DIAGNOSTICS = inheritedEnvironment.PI_NONO_DIAGNOSTICS === "1" ? "1" : "0";
      const { command, protectedPaths, credentialPaths, exposedCredentials } = yield* planLaunchCommand(args, process.cwd(), agentDir, home, environment, nono, rawPi, profile, envBinary, registry, inheritedEnvironment);
      if (exposedCredentials?.length) {
        console.warn(`pi sandbox launch: these credential files are outside the Pi credential store and stay readable on Linux: ${exposedCredentials.join(", ")}`);
      }
      if (command[0] === nono) command.splice(2, 0, "--log-file", environment.PI_NONO_DIAGNOSTICS_FILE!);
      // Herdr must identify the host-visible bootstrap even when nono hides the child process.
      process.title = "pi";
      if (command[0] !== nono) return yield* credentialProxySession(nono, profile, command, environment);
      // Herdr sees the foreground nono wrapper, not Pi's isolated process group.
      if (environment.HERDR_ENV === "1") environment.HERDR_AGENT = "pi";
      prepareJitiCache();
      prepareNpmCache();
      if (process.platform === "linux" && nonoProfile.network?.credentials?.length) {
        return yield* credentialProxySession(nono, profile, command, environment, { sandboxed: true });
      }
      command[command.indexOf("--profile") + 1] = yield* protectedShellProfile(profile, home, environment, process.platform, protectedPaths, credentialPaths);
      const result: ExitResult = spawnSync(command[0]!, command.slice(1), { stdio: "inherit", env: environment });
      return result;
    });
    // Resources are acquired in this order and released in reverse when the session ends.
    return yield* Effect.scoped(Effect.gen(function* () {
      let session = environment;
      if (ipcRestricted) session = yield* sessionServices(session, inheritedEnvironment, home);
      session = yield* ipcCapabilities(session, providerSession({ inherited: inheritedEnvironment, home, cwd: process.cwd(), agentDir, args }), registry, ipcRestricted ? "restricted" : "ordinary");
      // Every sandboxed session gets the host model executor, so the sandbox holds no credential file.
      // The invoking host, not a project .envrc, may opt out with PI_MODEL_EXECUTOR=0, for example
      // for Bedrock, which signs requests locally; the sandbox then reads the credential files itself.
      if (modelExecutorEnabled(inheritedEnvironment)) {
        session = yield* modelExecutor(session, modelExecutorEnvironment(inheritedEnvironment, agentDir), home, inheritedEnvironment.PI_MODEL_EXECUTOR_PACKAGE, inheritedEnvironment.PI_MODEL_EXECUTOR_MODELS || undefined);
      }
      return yield* runPi(session);
    }));
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [nono, rawPi, profile, direnv, envBinary, ...args] = process.argv.slice(2) as [string, string, string, string, string, ...string[]];
    if (args[0] === "--no-sandbox") execRawPi(rawPi, args.slice(1));
    const child = await Effect.runPromise(launchSandboxed(nono, rawPi, profile, direnv, envBinary, args));
    if (child.error) throw child.error;
    if (child.signal) process.kill(process.pid, child.signal);
    process.exit(child.status ?? 1);
  } catch (error) {
    console.error(`pi sandbox launch: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
}
