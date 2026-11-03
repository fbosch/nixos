import * as Effect from "effect/Effect";
import { existsSync, mkdirSync, readdirSync, realpathSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join } from "node:path";
import { fileURLToPath } from "node:url";
import { assertCredentialGrants } from "../credentials/grants.mts";
import { credentialFilesOutsideStore, credentialStoreDirectory } from "../credentials/store.mts";
import { assertCredentialSourceGrants } from "../credentials/definitions.mts";
import { assertPrivateIpcGrants, privateIpcPrefix } from "../ipc/private.mts";
import { defaultCapabilities, endpointArguments, selectCapabilities, type CapabilityRegistry, type SelectedCapabilities } from "../ipc/policy.mts";
import { serviceSocketArguments } from "../ipc/services.mts";
import { MODEL_EXECUTOR_SOCKET } from "../model-executor/launch.mts";
import { agentCredentialPaths, agentDirectories, agentProtection, type AgentProtection } from "../protection/agent.mts";
import { shellProtection } from "../protection/shell.mts";
import { existingDirectory, existingFile, readJsonFile, within } from "../shared/paths.mts";
import type { Environment, NonoProfile } from "../shared/types.mts";
import { gitMetadata, pairedRepositoryRoots, writableReferenceRoots } from "./git.mts";
import { approvedReferenceRoots, referenceApprovalStore, references } from "./references.mts";
import { sandboxRuntimeCommand } from "./runtime.mts";
import { assertReadOnlySshGrants, sshClientArguments } from "./ssh.mts";
import { GrantConflictError, LaunchPrerequisiteError, type SandboxError, attempt, runSyncOrThrow } from "../shared/errors.mts";
import { baseDirectory, grants, sandboxPolicy } from "../shared/sandbox-policy.mts";

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

// sops-nix Home Manager decrypts user secrets into %r/secrets.d and links the active generation from %r/secrets.
const runtimeSecretEntries = sandboxPolicy.filesystem.runtimeDirectory.secrets;
// Sandboxed tools cannot create top-level runtime entries, so create their directories before granting them.
const runtimeServiceDirectories = sandboxPolicy.filesystem.runtimeDirectory.services;

function runtimeDirectoryArguments(runtime: string, platform: NodeJS.Platform): string[] {
  if (platform !== "linux") return ["--allow", runtime];
  for (const name of runtimeServiceDirectories) mkdirSync(join(runtime, name), { recursive: true, mode: 0o700 });
  // Landlock cannot exclude a child of a granted directory, so grant top-level entries instead of the root.
  // Sockets need no grant while AF_UNIX mediation is off; symlinks are skipped so they cannot redirect a grant.
  return readdirSync(runtime, { withFileTypes: true }).flatMap((entry) => {
    if (runtimeSecretEntries.includes(entry.name)) return [];
    const path = join(runtime, entry.name);
    if (entry.isDirectory()) return ["--allow", path];
    return entry.isFile() ? ["--allow-file", path] : [];
  });
}

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

function assertHostOnlyGrants(args: readonly string[], cwd: string, hostOnlyPaths: readonly string[]): void {
  const separator = args.indexOf("--");
  const writable = [...(args.slice(0, separator).includes("--allow-cwd") ? [cwd] : []), ...args.slice(0, separator).flatMap((part, index, all) => ["--allow", "--allow-file"].includes(part) ? [all[index + 1]!] : [])];
  for (const path of writable) {
    const grant = existsSync(path) ? realpathSync(path) : path;
    const conflict = hostOnlyPaths.find((hostOnly) => within(hostOnly, grant) || within(grant, hostOnly));
    // Shell startup files and reference approvals act on the host; no writable grant may reach them.
    if (conflict !== undefined) throw new GrantConflictError({ message: `Writable launcher grant covers host-only path ${conflict}: ${path}; launch Pi from a directory that does not contain it.` });
  }
}

function assertRuntimeSecretGrants(args: readonly string[], cwd: string, home: string, environment: Environment, profile: NonoProfile, platform: NodeJS.Platform): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    const runtime = platform === "linux" && environment.XDG_RUNTIME_DIR ? yield* attempt(() => existingDirectory(environment.XDG_RUNTIME_DIR!)) : undefined;
    if (runtime === undefined) return;
    const secrets = runtimeSecretEntries.map((name) => join(runtime, name)).filter((path) => existsSync(path));
    yield* assertCredentialGrants(args, cwd, home, environment, profile, secrets, "Runtime secret");
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

// Without the executor, Pi in the sandbox reads and refreshes migrated credentials itself.
function addCredentialStoreGrants(home: string, agent: AgentProtection, grants: Set<string>, extra: string[]): void {
  for (const path of agent.authFiles) extra.push("--allow-file", path);
  let store: string | undefined;
  try { store = existingDirectory(credentialStoreDirectory(home)); } catch { store = undefined; }
  if (store === undefined) return;
  const auth = join(store, "auth.json");
  if (existingFile(auth)) extra.push("--allow-file", auth);
  const profiles = existingDirectory(join(store, "auth-profiles"));
  if (profiles !== undefined) grants.add(profiles);
}

function requireSocket(path: string, variable: string, message = `${variable} must be an absolute socket path`): void {
  if (!isAbsolute(path)) throw new LaunchPrerequisiteError({ message: message });
  if (!statSync(path).isSocket()) throw new LaunchPrerequisiteError({ message: `${variable} must point to a socket` });
}

/** Unix-socket grants for IPC capabilities, the model executor and the Neovim Pi Ask endpoint. */
function socketArguments(environment: Environment, home: string, capabilities: SelectedCapabilities, gitDirectories: Set<string>, ipcRestricted: boolean): { args: string[]; usesPrivateIpc: boolean } {
  const args = endpointArguments(capabilities, { "selected-git-metadata": [...gitDirectories] });
  const socketVariables = new Set(Object.values(capabilities).filter(capability => capability.backend === "json-lines").map(capability => capability.socketEnvironment));
  if (!ipcRestricted && environment.HERDR_ENV === "1") socketVariables.add("HERDR_SOCKET_PATH");
  if (ipcRestricted && environment.HERDR_ENV === "1" && environment.HERDR_SOCKET_PATH && !socketVariables.has("HERDR_SOCKET_PATH")) throw new LaunchPrerequisiteError({ message: "Herdr reporting is not enabled in the IPC capability profile" });
  for (const variable of socketVariables) {
    const socket = environment[variable];
    if (!socket) continue;
    requireSocket(socket, variable);
    args.push("--allow-unix-socket", socket);
  }
  const executorSocket = environment[MODEL_EXECUTOR_SOCKET];
  if (executorSocket) {
    // Only the launcher-owned executor endpoint is granted; it lives in private IPC state.
    if (!executorSocket.startsWith(privateIpcPrefix(home))) throw new LaunchPrerequisiteError({ message: `${MODEL_EXECUTOR_SOCKET} must be a private Pi IPC socket` });
    requireSocket(executorSocket, MODEL_EXECUTOR_SOCKET, `${MODEL_EXECUTOR_SOCKET} must be a private Pi IPC socket`);
    args.push("--allow-unix-socket", executorSocket);
  }
  const editorSocket = environment.PI_NVIM_ASK_SOCKET;
  if (environment.PI_NVIM_SOCKET && !editorSocket) throw new LaunchPrerequisiteError({ message: "Native Neovim RPC is not a Pi Ask endpoint; update both Pi Ask integrations" });
  if (editorSocket) {
    requireSocket(editorSocket, "PI_NVIM_ASK_SOCKET");
    args.push("--allow-unix-socket", editorSocket);
  }
  const usesPrivateIpc = [...socketVariables].some(variable => Boolean(environment[variable])) || Boolean(executorSocket || editorSocket || environment.AGENT_BROWSER_SOCKET_DIR);
  return { args, usesPrivateIpc };
}

/**
 * State that Pi extensions and editor integrations share with the host. Locations come from the
 * environment the launcher started with: a project .envrc must not choose writable grants.
 */
function toolStateArguments(environment: Environment, home: string, reads: Set<string>): string[] {
  const args: string[] = [];
  for (const grant of grants) {
    const path = (grant.override && environment[grant.override]) || join(baseDirectory(grant.base, home, environment), grant.path);
    if (grant.type === "file") {
      if (existingFile(path)) args.push("--read-file", path);
      continue;
    }
    const directory = existingDirectory(path);
    if (directory === undefined) continue;
    if (grant.access === "readwrite") args.push("--allow", path);
    // Read-only directories join the --read section, at their canonical location. For example,
    // direnv approvals are user-owned authorization; the sandbox may only consume existing decisions.
    else reads.add(directory);
  }
  return args;
}

function hostRuntimeArguments(environment: Environment, platform: NodeJS.Platform, ipcRestricted: boolean): string[] {
  const args: string[] = [];
  // Keep legacy behavior until the candidate passes the Linux development/desktop gates.
  if (!ipcRestricted && environment.XDG_RUNTIME_DIR) {
    const runtime = existingDirectory(environment.XDG_RUNTIME_DIR);
    if (runtime === undefined) {
      console.warn(`pi sandbox launch: XDG_RUNTIME_DIR is missing (${JSON.stringify(environment.XDG_RUNTIME_DIR)}); continuing without runtime-directory access.`);
    } else {
      args.push(...runtimeDirectoryArguments(runtime, platform));
    }
  }
  // grim and other Wayland clients allocate buffers with shm_open; its flat names cannot be scoped per tool.
  // Both profiles permit native screenshots and the accompanying access to unrelated same-user shared memory.
  const sharedMemory = platform === "linux" ? existingDirectory("/dev/shm") : undefined;
  if (sharedMemory !== undefined) args.push("--allow", sharedMemory);
  return args;
}

/** Reject a finished command line whose grants reach private IPC, SSH, credential or host-only paths. */
interface LaunchGrantContext {
  cwd: string;
  home: string;
  environment: Environment;
  loadedProfile: NonoProfile;
  platform: NodeJS.Platform;
  usesPrivateIpc: boolean;
  hostOnlyPaths: readonly string[];
  approvals: string;
  credentialPaths: readonly string[];
}

function assertLaunchGrants(args: readonly string[], { cwd, home, environment, loadedProfile, platform, usesPrivateIpc, hostOnlyPaths, approvals, credentialPaths }: LaunchGrantContext): Effect.Effect<void, SandboxError> {
  return Effect.gen(function* () {
    if (usesPrivateIpc) yield* assertPrivateIpcGrants(args, cwd, home);
    yield* assertReadOnlySshGrants(args, cwd);
    const guardEnvironment = { ...environment, TMPDIR: environment.TMPDIR || tmpdir() };
    yield* assertCredentialSourceGrants(args, cwd, home, guardEnvironment, loadedProfile);
    yield* assertRuntimeSecretGrants(args, cwd, home, guardEnvironment, loadedProfile, platform);
    yield* attempt(() => assertHostOnlyGrants(args, cwd, platform === "linux" ? hostOnlyPaths : [approvals]));
    if (credentialPaths.length > 0 && (yield* attempt(() => existingDirectory(home))) !== undefined) {
      // No grant, including profile reads, may reach the credential store in executor mode.
      yield* assertCredentialGrants(args, cwd, home, guardEnvironment, loadedProfile, [credentialStoreDirectory(home)], "Pi");
    }
  });
}

// `hostEnvironment` defaults to `environment` only for callers without a project environment, such as tests.
function planLaunchArguments(cwd: string, agentDir: string, home: string, environment: Environment, profile: string, rawPi: string, envBinary: string, platform: NodeJS.Platform = process.platform, registry: CapabilityRegistry = defaultCapabilities, hostEnvironment: Environment = environment): Effect.Effect<LaunchPlan, SandboxError> {
  return Effect.gen(function* () {
    if (!isAbsolute(profile) || !existingFile(profile)) return yield* new LaunchPrerequisiteError({ message: `Nix nono profile missing: ${profile}` });
    if (!isAbsolute(envBinary) || !existingFile(envBinary)) return yield* new LaunchPrerequisiteError({ message: `Nix env executable missing: ${envBinary}` });
    // The Nix-generated profile is a JSON object; nono validates its full schema.
    const loadedProfile = (yield* attempt(() => readJsonFile(profile, "nono profile"))) as NonoProfile;
    const ipcRestricted = loadedProfile?.linux?.af_unix_mediation === "pathname";
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
    const extra = [...yield* sshClientArguments(home, environment), ...yield* serviceSocketArguments(cwd, home, environment, ipcRestricted)];
    let agent: AgentProtection = { protectedPaths: [], runtimePaths: [], authFiles: [] };
    if (writableRoots.length > 0) {
      // Configuration sessions may persist Pi changes on either OS; other host-only guards still apply.
      for (const root of yield* agentDirectories(home, agentDir)) grants.add(root);
    } else {
      agent = yield* agentProtection(home, agentDir, environment, loadedProfile, platform);
    }
    // Executor mode: credential files belong to the host executor, so the sandbox gets no grant to them.
    const credentialPaths = environment[MODEL_EXECUTOR_SOCKET] ? yield* agentCredentialPaths(home, agentDir) : [];
    const credentialStore = (path: string) => credentialPaths.some((credential) => within(path, credential));
    for (const path of agent.runtimePaths) if (!credentialStore(path)) grants.add(path);
    if (credentialPaths.length === 0) yield* attempt(() => addCredentialStoreGrants(home, agent, grants, extra));
    const sockets = yield* attempt(() => socketArguments(environment, home, capabilities, gitDirectories, ipcRestricted));
    extra.push(...sockets.args, ...yield* attempt(() => toolStateArguments(hostEnvironment, home, reads)), ...yield* attempt(() => hostRuntimeArguments(environment, platform, ipcRestricted)));
    // Seatbelt denies startup writes on macOS; Linux must keep them outside every writable grant instead.
    const approvals = dirname(referenceApprovalStore(home));
    const shellPaths = platform === "linux" && (yield* attempt(() => existingDirectory(home))) !== undefined ? (yield* shellProtection(home, environment)).protectedPaths : [];
    const hostOnlyPaths = [
      ...shellPaths,
      ...agent.protectedPaths,
      approvals,
      // macOS denies credential stores in the session profile instead, so config sessions keep their cwd grant.
      ...(platform === "linux" ? credentialPaths : []),
    ];
    const canonicalCwd = realpathSync(cwd);
    // A cwd that contains host-only paths is split like any other grant, so nono's whole-directory workdir grant is withheld.
    const splitCwd = platform === "linux" && hostOnlyPaths.some((path) => within(path, canonicalCwd) || within(canonicalCwd, path));
    if (splitCwd) grants.add(canonicalCwd);
    const split: SplitGrants = { allow: [], files: [], reads: [] };
    for (const path of grants) splitWritableGrant(path, platform === "linux" ? hostOnlyPaths : [...agent.protectedPaths, ...credentialPaths], split);
    const args = [
      "run", "--profile", profile, ...(splitCwd ? [] : ["--allow-cwd"]), "--suppress-save-prompt", "/",
      ...(platform === "darwin" ? ["--trust-proxy-ca"] : []),
      // No direct-egress ports: Landlock port grants admit every host, so all traffic must cross the nono proxy.
      ...extra,
      ...[...new Set([...reads, ...split.reads])].filter((path) => !split.allow.includes(path)).flatMap((path) => ["--read", path]),
      ...split.allow.flatMap((path) => ["--allow", path]),
      ...split.files.flatMap((path) => ["--allow-file", path]),
      "--", ...sandboxRuntimeCommand(home, rawPi, envBinary),
    ];
    yield* assertLaunchGrants(args, { cwd, home, environment, loadedProfile, platform, usesPrivateIpc: sockets.usesPrivateIpc, hostOnlyPaths, approvals, credentialPaths });
    // Landlock cannot hide regular files inside a readable agent directory; only store links are safe.
    const exposedCredentials = credentialPaths.length > 0 && platform === "linux"
      ? credentialFilesOutsideStore(yield* agentDirectories(home, agentDir))
      : [];
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
