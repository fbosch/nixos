import * as Effect from "effect/Effect";
import { existsSync, readdirSync, realpathSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { assertCredentialGrants } from "../credentials/grants.mts";
import { assertCredentialSourceGrants } from "../credentials/definitions.mts";
import { assertPrivateIpcGrants, privateIpcPrefix } from "../ipc/private.mts";
import { defaultCapabilities, endpointGrants, selectCapabilities, type CapabilityRegistry, type SelectedCapabilities } from "../ipc/policy.mts";
import { serviceSocketGrants } from "../ipc/services.mts";
import { MODEL_EXECUTOR_SOCKET } from "../model-executor/launch.mts";
import { agentDirectories, agentProtection, type AgentProtection } from "../protection/agent.mts";
import { existingDirectory, existingFile, within } from "../shared/paths.mts";
import type { Environment, NonoProfile } from "../shared/types.mts";
import { gitMetadata, pairedRepositoryRoots, writableReferenceRoots } from "./git.mts";
import { approvedReferenceRoots, referenceApprovalStore, references } from "./references.mts";
import { sandboxRuntimeCommand } from "./runtime.mts";
import { assertReadOnlySshGrants, sshClientGrants } from "./ssh.mts";
import { GrantConflictError, LaunchPrerequisiteError, type SandboxError, attempt, runSyncOrThrow } from "../shared/errors.mts";
import { baseDirectory, grants as toolGrants, sandboxPolicy } from "../shared/sandbox-policy.mts";
import { grant, grantedPaths, grantPlan, toArguments, writableFlags, type Grant, type GrantPlan } from "../shared/grant-plan.mts";
import { readNonoProfile } from "../shared/nono-profile.mts";
import type { Confinement } from "./platform/confinement.mts";
import { confinementFor } from "./platform/select.mts";
import { assertCredentialPosture, credentialPosture, hostOnlyCredentials, writableRuntimePath, type CredentialPosture } from "./credential-posture.mts";

// Builds the nono command line for one session: filesystem, socket and credential grants plus
// the guards that reject any grant reaching host-only or credential paths.

/** Grants that splitWritableGrant produced from writable roots. */
interface SplitGrants {
  allow: string[];
  files: string[];
  reads: string[];
}

/** Grants collected for one session before they are split around protected paths. */
interface GrantSets {
  grants: Set<string>;
  reads: Set<string>;
  gitDirectories: Set<string>;
}

interface LaunchPlan {
  args: string[];
  /** Paths that macOS profile generation must keep read-only. */
  protectedPaths: string[];
  credentialPaths: string[];
  /** Linux: credential files left outside the store, and therefore readable. */
  exposedCredentials: string[];
}

export interface LaunchCommandPlan {
  command: string[];
  protectedPaths: string[];
  credentialPaths?: string[];
  exposedCredentials?: string[];
}

type LaunchArgumentsParameters = [cwd: string, agentDir: string, home: string, environment: Environment, profile: string, rawPi: string, envBinary: string, platform?: NodeJS.Platform, registry?: CapabilityRegistry, hostEnvironment?: Environment];
type LaunchCommandParameters = [args: string[], cwd: string, agentDir: string, home: string, environment: Environment, nono: string, rawPi: string, profile: string, envBinary: string, registry?: CapabilityRegistry, hostEnvironment?: Environment];

// Landlock cannot subtract a child from a writable grant, so a root containing protected paths is split into its siblings.
function splitWritableGrant(root: string, protectedPaths: readonly string[], split: SplitGrants): void {
  if (protectedPaths.some((path) => within(root, path))) {
    split.reads.push(root);
    return;
  }
  const inside = protectedPaths.filter((path) => within(path, root));
  if (inside.length === 0) {
    split.allow.push(root);
    return;
  }
  // The split level itself stays read-only: no new entries can appear beside protected ones.
  split.reads.push(root);
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const path = join(root, entry.name);
    // A grant follows symlinks, so an aliased entry could re-expose a protected target.
    if (entry.isSymbolicLink()) continue;
    if (entry.isDirectory()) splitWritableGrant(path, inside, split);
    else if (entry.isFile() && !inside.includes(path)) split.files.push(path);
  }
}

function assertHostOnlyGrants(plan: GrantPlan, cwd: string, hostOnlyPaths: readonly string[]): void {
  const writable = [...(plan.allowCwd ? [cwd] : []), ...grantedPaths(plan, writableFlags)];
  for (const path of writable) {
    const grant = existsSync(path) ? realpathSync(path) : path;
    const conflict = hostOnlyPaths.find((hostOnly) => within(hostOnly, grant) || within(grant, hostOnly));
    // Shell startup files and reference approvals act on the host; no writable grant may reach them.
    if (conflict !== undefined) throw new GrantConflictError({ message: `Writable launcher grant covers host-only path ${conflict}: ${path}; launch Pi from a directory that does not contain it.` });
  }
}

function assertRuntimeSecretGrants(plan: GrantPlan, cwd: string, home: string, environment: Environment, profile: NonoProfile, confinement: Confinement): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    const secrets = yield* confinement.runtimeSecrets(environment);
    if (secrets === undefined) return;
    yield* assertCredentialGrants(plan, cwd, home, environment, profile, secrets, "Runtime secret");
  });
}

/** Synchronous entry for callers outside Effect; rethrows the original sandbox error. */
export function launchArguments(...parameters: LaunchArgumentsParameters): string[] {
  return runSyncOrThrow(planLaunchArguments(...parameters)).args;
}

// Approved references become writable inside configuration sessions and read-only elsewhere.
function addReferenceGrants(cwd: string, agentDir: string, home: string, writableRoots: readonly string[], needsGitSockets: boolean, { grants, reads, gitDirectories }: GrantSets): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    const approvedRoots = [realpathSync(cwd), ...yield* pairedRepositoryRoots(home), ...yield* approvedReferenceRoots(home)];
    for (const reference of yield* references(cwd, agentDir, home)) {
      const path = yield* attempt(() => existingDirectory(reference.path));
      if (path === undefined) continue;
      if (!approvedRoots.some((root) => within(path, root))) {
        console.warn(`pi sandbox launch: skipping unapproved reference ${JSON.stringify(reference.name)} (${path}); approve it on the host by adding the path to ${referenceApprovalStore(home)}.`);
        continue;
      }
      if (needsGitSockets) {
        const directory = (yield* gitMetadata(path, home)).directory;
        if (directory) gitDirectories.add(directory);
      }
      const destinations = writableRoots.some((root) => within(path, root)) ? grants : reads;
      destinations.add(path);
    }
  });
}

function requireSocket(path: string, variable: string, message = `${variable} must be an absolute socket path`): void {
  if (!isAbsolute(path)) throw new LaunchPrerequisiteError({ message: message });
  if (!statSync(path).isSocket()) throw new LaunchPrerequisiteError({ message: `${variable} must point to a socket` });
}

/** Unix-socket grants for IPC capabilities, the model executor and the Neovim Pi Ask endpoint. */
function socketGrants(environment: Environment, home: string, capabilities: SelectedCapabilities, gitDirectories: Set<string>, ipcRestricted: boolean): { grants: Grant[]; usesPrivateIpc: boolean } {
  const grants = endpointGrants(capabilities, { "selected-git-metadata": [...gitDirectories] });
  const socketVariables = new Set(Object.values(capabilities).filter(capability => capability.backend === "json-lines").map(capability => capability.socketEnvironment));
  if (!ipcRestricted && environment.HERDR_ENV === "1") socketVariables.add("HERDR_SOCKET_PATH");
  if (ipcRestricted && environment.HERDR_ENV === "1" && environment.HERDR_SOCKET_PATH && !socketVariables.has("HERDR_SOCKET_PATH")) throw new LaunchPrerequisiteError({ message: "Herdr reporting is not enabled in the IPC capability profile" });
  for (const variable of socketVariables) {
    const socket = environment[variable];
    if (!socket) continue;
    requireSocket(socket, variable);
    grants.push(grant("--allow-unix-socket", socket));
  }
  const executorSocket = environment[MODEL_EXECUTOR_SOCKET];
  if (executorSocket) {
    // Only the launcher-owned executor endpoint is granted; it lives in private IPC state.
    if (!executorSocket.startsWith(privateIpcPrefix(home))) throw new LaunchPrerequisiteError({ message: `${MODEL_EXECUTOR_SOCKET} must be a private Pi IPC socket` });
    requireSocket(executorSocket, MODEL_EXECUTOR_SOCKET, `${MODEL_EXECUTOR_SOCKET} must be a private Pi IPC socket`);
    grants.push(grant("--allow-unix-socket", executorSocket));
  }
  const editorSocket = environment.PI_NVIM_ASK_SOCKET;
  if (environment.PI_NVIM_SOCKET && !editorSocket) throw new LaunchPrerequisiteError({ message: "Native Neovim RPC is not a Pi Ask endpoint; update both Pi Ask integrations" });
  if (editorSocket) {
    requireSocket(editorSocket, "PI_NVIM_ASK_SOCKET");
    grants.push(grant("--allow-unix-socket", editorSocket));
  }
  const usesPrivateIpc = [...socketVariables].some(variable => Boolean(environment[variable])) || Boolean(executorSocket || editorSocket || environment.AGENT_BROWSER_SOCKET_DIR);
  return { grants, usesPrivateIpc };
}

/**
 * State that Pi extensions and editor integrations share with the host. Locations come from the
 * environment the launcher started with: a project .envrc must not choose writable grants.
 */
function toolStateGrants(environment: Environment, home: string, reads: Set<string>): Grant[] {
  const grants: Grant[] = [];
  for (const tool of toolGrants) {
    const path = (tool.override && environment[tool.override]) || join(baseDirectory(tool.base, home, environment), tool.path);
    if (tool.type === "file") {
      if (existingFile(path)) grants.push(grant("--read-file", path));
      continue;
    }
    const directory = existingDirectory(path);
    if (directory === undefined) continue;
    if (tool.access === "readwrite") grants.push(grant("--allow", path));
    // Read-only directories join the --read section, at their canonical location. For example,
    // direnv approvals are user-owned authorization; the sandbox may only consume existing decisions.
    else reads.add(directory);
  }
  return grants;
}

function hostRuntimeGrants(environment: Environment, confinement: Confinement, ipcRestricted: boolean): Grant[] {
  const grants: Grant[] = [];
  // Keep legacy behavior until the candidate passes the Linux development/desktop gates.
  if (!ipcRestricted && environment.XDG_RUNTIME_DIR) {
    const runtime = existingDirectory(environment.XDG_RUNTIME_DIR);
    if (runtime === undefined) {
      console.warn(`pi sandbox launch: XDG_RUNTIME_DIR is missing (${JSON.stringify(environment.XDG_RUNTIME_DIR)}); continuing without runtime-directory access.`);
    } else {
      grants.push(...confinement.runtimeDirectoryGrants(runtime));
    }
  }
  grants.push(...confinement.sharedMemoryGrants());
  return grants;
}

/** Reject a grant plan that reaches private IPC, SSH, credential or host-only paths. */
interface LaunchGrantContext {
  cwd: string;
  home: string;
  environment: Environment;
  loadedProfile: NonoProfile;
  confinement: Confinement;
  usesPrivateIpc: boolean;
  guarded: readonly string[];
  posture: CredentialPosture;
}

function assertLaunchGrants(plan: GrantPlan, { cwd, home, environment, loadedProfile, confinement, usesPrivateIpc, guarded, posture }: LaunchGrantContext): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    if (usesPrivateIpc) yield* assertPrivateIpcGrants(plan, cwd, home);
    yield* assertReadOnlySshGrants(plan, cwd);
    const guardEnvironment = { ...environment, TMPDIR: environment.TMPDIR || tmpdir() };
    yield* assertCredentialSourceGrants(plan, cwd, home, guardEnvironment, loadedProfile);
    yield* assertRuntimeSecretGrants(plan, cwd, home, guardEnvironment, loadedProfile, confinement);
    yield* attempt(() => assertHostOnlyGrants(plan, cwd, guarded));
    yield* assertCredentialPosture(posture, plan, cwd, home, guardEnvironment, loadedProfile);
  });
}

// `hostEnvironment` defaults to `environment` only for callers without a project environment, such as tests.
function planLaunchArguments(cwd: string, agentDir: string, home: string, environment: Environment, profile: string, rawPi: string, envBinary: string, platform: NodeJS.Platform = process.platform, registry: CapabilityRegistry = defaultCapabilities, hostEnvironment: Environment = environment): Effect.Effect<LaunchPlan, SandboxError> {
  return Effect.gen(function* () {
    const confinement = confinementFor(platform);
    const loadedProfile = yield* attempt(() => readNonoProfile(profile));
    if (!isAbsolute(envBinary) || !existingFile(envBinary)) return yield* new LaunchPrerequisiteError({ message: `Nix env executable missing: ${envBinary}` });
    const ipcRestricted = loadedProfile.linux?.af_unix_mediation === "pathname";
    const capabilities = selectCapabilities(registry, ipcRestricted ? "restricted" : "ordinary", platform);
    const needsGitSockets = Object.values(capabilities).some(capability => capability.backend === "endpoint" && capability.discovery === "selected-git-metadata");
    const metadata = yield* gitMetadata(cwd, home);
    const grants = new Set(metadata.roots);
    const gitDirectories = new Set(metadata.directory ? [metadata.directory] : []);
    const reads = new Set<string>();
    const writableRoots = yield* writableReferenceRoots(cwd, home, metadata);
    yield* addReferenceGrants(cwd, agentDir, home, writableRoots, needsGitSockets, { grants, reads, gitDirectories });
    // Stow links extension resources into the repo; only grant their actual targets.
    for (const path of [agentDir, ...sandboxPolicy.filesystem.agent.writableHomePaths.map((path) => join(home, path))]) {
      const canonical = yield* attempt(() => existingDirectory(path));
      if (canonical !== undefined) grants.add(canonical);
    }
    const extra = [...yield* sshClientGrants(home, environment), ...yield* serviceSocketGrants(cwd, home, environment, ipcRestricted)];
    let agent: AgentProtection = { protectedPaths: [], runtimePaths: [], authFiles: [] };
    if (writableRoots.length > 0) {
      // Configuration sessions may persist Pi changes on either OS; other host-only guards still apply.
      for (const root of yield* agentDirectories(home, agentDir)) grants.add(root);
    } else {
      agent = yield* agentProtection(home, agentDir, environment, loadedProfile, platform);
    }
    const posture = yield* credentialPosture(home, agentDir, environment, agent);
    const credentialPaths = hostOnlyCredentials(posture);
    for (const path of agent.runtimePaths) if (writableRuntimePath(posture, path)) grants.add(path);
    if (posture.mode === "sandbox") {
      extra.push(...posture.files);
      for (const directory of posture.directories) grants.add(directory);
    }
    const sockets = yield* attempt(() => socketGrants(environment, home, capabilities, gitDirectories, ipcRestricted));
    extra.push(...sockets.grants, ...yield* attempt(() => toolStateGrants(hostEnvironment, home, reads)), ...yield* attempt(() => hostRuntimeGrants(environment, confinement, ipcRestricted)));
    const approvals = dirname(referenceApprovalStore(home));
    const protections = yield* confinement.protections({ home, environment, agent, approvals, credentialPaths });
    const canonicalCwd = realpathSync(cwd);
    // A cwd that contains protected paths is split like any other grant, so nono's whole-directory workdir grant is withheld.
    const splitCwd = protections.splitCwd && protections.splitAround.some((path) => within(path, canonicalCwd) || within(canonicalCwd, path));
    if (splitCwd) grants.add(canonicalCwd);
    const split: SplitGrants = { allow: [], files: [], reads: [] };
    for (const path of grants) splitWritableGrant(path, protections.splitAround, split);
    const plan = grantPlan([
      ...extra,
      ...[...new Set([...reads, ...split.reads])].filter((path) => !split.allow.includes(path)).map((path) => grant("--read", path)),
      ...split.allow.map((path) => grant("--allow", path)),
      ...split.files.map((path) => grant("--allow-file", path)),
    ], !splitCwd);
    yield* assertLaunchGrants(plan, { cwd, home, environment, loadedProfile, confinement, usesPrivateIpc: sockets.usesPrivateIpc, guarded: protections.guarded, posture });
    const exposedCredentials = posture.mode === "executor" ? confinement.exposedCredentials(yield* agentDirectories(home, agentDir)) : [];
    // No direct-egress ports: Landlock port grants admit every host, so all traffic must cross the nono proxy.
    const args = [
      "run", "--profile", profile, ...(plan.allowCwd ? ["--allow-cwd"] : []), "--suppress-save-prompt", "/",
      ...confinement.runFlags,
      ...toArguments(plan.grants),
      "--", ...sandboxRuntimeCommand(home, rawPi, envBinary),
    ];
    return { args, protectedPaths: [...agent.protectedPaths, approvals], credentialPaths, exposedCredentials };
  });
}

/** Synchronous entry for callers outside Effect; rethrows the original sandbox error. */
export function launchCommand(...parameters: LaunchCommandParameters): string[] {
  return runSyncOrThrow(planLaunchCommand(...parameters)).command;
}

/** The complete nono command for a session, or raw Pi for an explicit `--no-sandbox` launch. */
export function planLaunchCommand(args: string[], cwd: string, agentDir: string, home: string, environment: Environment, nono: string, rawPi: string, profile: string, envBinary: string, registry: CapabilityRegistry = defaultCapabilities, hostEnvironment: Environment = environment): Effect.Effect<LaunchCommandPlan, SandboxError> {
  return Effect.gen(function* () {
    if (!isAbsolute(rawPi) || !existsSync(rawPi)) return yield* new LaunchPrerequisiteError({ message: `Raw Pi executable missing: ${rawPi}` });
    if (args[0] === "--no-sandbox") return { command: [rawPi, ...args.slice(1)], protectedPaths: [] };
    const extension = environment.PI_NONO_DIAGNOSTICS === "1" && environment.PI_NONO_DIAGNOSTICS_FILE
      ? ["--extension", fileURLToPath(new URL("./diagnostics-extension.mts", import.meta.url))]
      : [];
    if (!isAbsolute(nono) || !existsSync(nono)) return yield* new LaunchPrerequisiteError({ message: `nono executable missing: ${nono}` });
    const plan = yield* planLaunchArguments(cwd, agentDir, home, environment, profile, rawPi, envBinary, process.platform, registry, hostEnvironment);
    return { command: [nono, ...plan.args, ...extension, ...args], protectedPaths: plan.protectedPaths, credentialPaths: plan.credentialPaths, exposedCredentials: plan.exposedCredentials };
  });
}
