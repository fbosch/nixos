import { existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, statSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { delimiter, dirname, isAbsolute, join, resolve, sep } from "node:path";
import { spawnSync } from "node:child_process";
import { pathToFileURL } from "node:url";
import { stripVTControlCharacters } from "node:util";
import { withProtectedShellProfile } from "./shell-protection.mjs";
import { assertReadOnlySshGrants, sshClientArguments } from "./ssh-access.mjs";
import { assertCredentialSourceGrants, credentialEnvironmentForDirenv, prepareCredentialEnvironment } from "./credentials.mjs";
import { prepareSandboxRuntime, sandboxRuntimeCommand } from "./sandbox-runtime.mjs";
import { runWithCredentialProxy } from "./credential-proxy.mjs";
import { assertPrivateIpcGrants } from "./private-ipc.mjs";
import { assertCredentialGrants } from "./credential-grants.mjs";
import { withIpcCapabilities } from "./ipc-session.mjs";
import { serviceSocketArguments, withSessionServiceEnvironment } from "./service-ipc.mjs";
import { defaultCapabilities, endpointArguments, loadCapabilities, selectCapabilities } from "./ipc-policy.mjs";

function record(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function existingDirectory(path) {
  if (!existsSync(path)) return undefined;
  const canonical = realpathSync(path);
  if (!statSync(canonical).isDirectory()) throw new Error(`Not a directory: ${path}`);
  return canonical;
}

function readJson(path, label) {
  if (!existsSync(path)) return undefined;
  try {
    return JSON.parse(readFileSync(path, "utf8").replace(/^\uFEFF/, ""));
  } catch (error) {
    throw new Error(`Cannot load ${label} from ${path}: ${error.message}`);
  }
}

function configuredReferences(settingsPath, base, home) {
  const settings = readJson(settingsPath, "project references");
  if (settings === undefined) return [];
  if (!record(settings)) throw new Error(`Project settings must contain a JSON object: ${settingsPath}`);
  if (settings.references === undefined) return [];
  if (!record(settings.references)) throw new Error(`Project references must contain an object: ${settingsPath}`);
  return Object.entries(settings.references).flatMap(([name, entry]) => {
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error(`Invalid project reference name: ${name}`);
    if (!record(entry)) throw new Error(`Project reference "${name}" must contain an object.`);
    const path = typeof entry.path === "string" ? entry.path.trim() : "";
    const description = typeof entry.description === "string" ? entry.description.trim() : "";
    if (!path) throw new Error(`Project reference "${name}" requires a path.`);
    if (!description) throw new Error(`Project reference "${name}" requires a description.`);
    const expanded = path === "~" ? home : path.startsWith("~/") ? join(home, path.slice(2)) : path;
    const absolute = isAbsolute(expanded) ? expanded : resolve(base, expanded);
    if (!existsSync(absolute)) return [];
    const canonical = realpathSync(absolute);
    if (!statSync(canonical).isDirectory()) throw new Error(`Reference path is not a directory: ${path}`);
    return [{ name, path: canonical }];
  });
}

function docsCacheReferences(cwd) {
  const lock = readJson(join(cwd, "docs-lock.json"), "docs-cache references");
  if (lock === undefined) return [];
  if (!record(lock) || lock.version !== 1 || !record(lock.sources)) {
    throw new Error(`Invalid docs-cache lock file: ${join(cwd, "docs-lock.json")}`);
  }
  return Object.entries(lock.sources).map(([name, entry]) => {
    if (!name || name.length > 200 || /[<>:"/\\|?*\x00-\x1f\x7f]/.test(name) || /[.\s]$/u.test(name) ||
        [".", "..", "CON", "PRN", "AUX", "NUL", "COM1", "LPT1"].includes(name.toUpperCase())) {
      throw new Error(`Invalid docs-cache reference name: ${name}`);
    }
    if (!record(entry) || typeof entry.repo !== "string" || !entry.repo.trim()) {
      throw new Error(`Docs-cache source "${name}" requires a repository.`);
    }
    const path = resolve(cwd, ".docs", name);
    return { name, path: existsSync(path) ? realpathSync(path) : path };
  });
}

function projectTrusted(cwd, agentDir, home) {
  const project = join(cwd, ".pi");
  const localResources = ["settings.json", "mcp.json", "extensions", "skills", "prompts", "themes", "SYSTEM.md", "APPEND_SYSTEM.md"]
    .some((name) => existsSync(join(project, name)));
  const canonical = realpathSync(cwd);
  const ancestors = [];
  for (let path = canonical; ; path = dirname(path)) {
    ancestors.push(path);
    if (path === dirname(path)) break;
  }
  const userSkills = join(existingDirectory(home) ?? resolve(home), ".agents", "skills");
  if (!localResources && !ancestors.some((path) => {
    const skills = join(path, ".agents", "skills");
    return skills !== userSkills && existsSync(skills);
  })) return true;
  const decisions = readJson(join(agentDir, "trust.json"), "project trust");
  if (decisions === undefined) return false;
  if (!record(decisions) || Object.values(decisions).some((value) => value !== true && value !== false && value !== null)) {
    throw new Error(`Invalid project trust store: ${join(agentDir, "trust.json")}`);
  }
  // A saved ancestor decision applies to descendants; the nearest decision wins.
  for (const path of ancestors) {
    if (decisions[path] === true) return true;
    if (decisions[path] === false) return false;
  }
  return false;
}

function references(cwd, agentDir, home) {
  const trusted = projectTrusted(cwd, agentDir, home);
  const canonicalCwd = realpathSync(cwd);
  const global = configuredReferences(join(agentDir, "settings.json"), agentDir, home);
  const project = trusted ? configuredReferences(join(cwd, ".pi", "settings.json"), cwd, home) : [];
  const merged = new Map([...global, ...project].map((reference) => [reference.name.toLowerCase(), reference]));
  for (const [name, reference] of merged) {
    if (reference.path === canonicalCwd) merged.delete(name);
  }
  const docs = (trusted ? docsCacheReferences(cwd) : []).filter((reference) => reference.path !== canonicalCwd);
  for (const reference of docs) {
    if (merged.has(reference.name.toLowerCase())) {
      throw new Error(`Docs-cache reference "${reference.name}" conflicts with configured reference "${merged.get(reference.name.toLowerCase()).name}".`);
    }
  }
  return [...merged.values(), ...docs];
}

function existingFile(path) {
  return existsSync(path) && statSync(path).isFile();
}

function within(path, root) {
  return root === sep || path === root || path.startsWith(`${root}${sep}`);
}

function gitMetadata(cwd, home) {
  const canonicalCwd = realpathSync(cwd);
  const canonicalHome = existingDirectory(home) ?? resolve(home);
  for (let root = canonicalCwd; ; root = dirname(root)) {
    const marker = join(root, ".git");
    let entry;
    try {
      entry = lstatSync(marker);
    } catch (error) {
      if (error.code !== "ENOENT") throw new Error(`Cannot inspect Git metadata at ${marker}: ${error.message}`);
      if (root === dirname(root)) return { roots: [] };
      continue;
    }
    try {
      let metadata;
      let gitDir;
      if (entry.isDirectory()) {
        metadata = realpathSync(marker);
      } else if (entry.isFile()) {
        const pointer = /^gitdir: ([^\r\n\x00]+)\r?\n?$/.exec(readFileSync(marker, "utf8"));
        if (!pointer) throw new Error("Invalid .git worktree pointer");
        gitDir = realpathSync(resolve(root, pointer[1]));
        if (!statSync(gitDir).isDirectory()) throw new Error("Worktree Git path is not a directory");
        const readPath = (name) => {
          const path = readFileSync(join(gitDir, name), "utf8").replace(/\r?\n$/, "");
          if (!path || /[\x00-\x1f\x7f]/.test(path)) throw new Error(`Invalid worktree ${name} path`);
          return resolve(gitDir, path);
        };
        metadata = realpathSync(readPath("commondir"));
        if (!statSync(metadata).isDirectory()) throw new Error("Shared Git path is not a directory");
        // A mutable .git pointer must not authorize arbitrary directories or another checkout's metadata.
        if (dirname(gitDir) !== join(metadata, "worktrees") || realpathSync(readPath("gitdir")) !== marker) {
          throw new Error("Git worktree registration does not match this checkout");
        }
        if (!statSync(join(metadata, "HEAD")).isFile() ||
            !statSync(join(metadata, "objects")).isDirectory() || !statSync(join(metadata, "refs")).isDirectory()) {
          throw new Error("Shared directory is not Git repository metadata");
        }
      } else {
        throw new Error(".git must be a directory or a regular worktree pointer file");
      }
      if (within(canonicalHome, metadata) || within(root, metadata)) {
        throw new Error("Git metadata must not resolve to the home directory or a checkout ancestor");
      }
      // Indexes, locks, refs and objects need writes; granting only worktrees/<name> is insufficient.
      return { roots: within(metadata, canonicalCwd) ? [] : [metadata], directory: gitDir ?? metadata };
    } catch (error) {
      throw new Error(`Cannot resolve Git metadata from ${marker}: ${error.message}`);
    }
  }
}

function writableReferenceRoots(cwd, home) {
  // These exceptions are packaged by Nix, never selected by mutable reference names or settings.
  const roots = ["dotfiles", "nixos"].map((name) => existingDirectory(join(home, name))).filter(Boolean);
  if (roots.length === 0) return [];
  const canonicalHome = realpathSync(home);
  if (roots.some((root) => within(canonicalHome, root))) {
    throw new Error("Paired repository paths must not resolve to the home directory or an ancestor.");
  }
  const canonicalCwd = realpathSync(cwd);
  return roots.some((root) => within(canonicalCwd, root)) ? roots : [];
}

// sops-nix Home Manager decrypts user secrets into %r/secrets.d and links the active generation from %r/secrets.
const runtimeSecretEntries = ["secrets", "secrets.d"];

function runtimeDirectoryArguments(runtime, platform) {
  if (platform !== "linux") return ["--allow", runtime];
  // Landlock cannot exclude a child of a granted directory, so grant top-level entries instead of the root.
  // Sockets need no grant while AF_UNIX mediation is off; symlinks are skipped so they cannot redirect a grant.
  return readdirSync(runtime, { withFileTypes: true }).flatMap((entry) => {
    if (runtimeSecretEntries.includes(entry.name)) return [];
    const path = join(runtime, entry.name);
    if (entry.isDirectory()) return ["--allow", path];
    return entry.isFile() ? ["--allow-file", path] : [];
  });
}

function assertRuntimeSecretGrants(args, cwd, home, environment, profile, platform) {
  const runtime = platform === "linux" && environment.XDG_RUNTIME_DIR ? existingDirectory(environment.XDG_RUNTIME_DIR) : undefined;
  if (runtime === undefined) return;
  const secrets = runtimeSecretEntries.map((name) => join(runtime, name)).filter((path) => existsSync(path));
  assertCredentialGrants(args, cwd, home, environment, profile, secrets, "Runtime secret");
}

export function launchArguments(cwd, agentDir, home, environment, profile, rawPi, envBinary, platform = process.platform, registry = defaultCapabilities) {
  if (!isAbsolute(profile) || !existingFile(profile)) throw new Error(`Nix nono profile missing: ${profile}`);
  if (!isAbsolute(envBinary) || !existingFile(envBinary)) throw new Error(`Nix env executable missing: ${envBinary}`);
  const ipcRestricted = readJson(profile, "nono profile")?.linux?.af_unix_mediation === "pathname";
  const capabilities = selectCapabilities(registry, ipcRestricted ? "restricted" : "ordinary", platform);
  const needsGitSockets = Object.values(capabilities).some(capability => capability.backend === "endpoint" && capability.discovery === "selected-git-metadata");
  const metadata = gitMetadata(cwd, home);
  const grants = new Set(metadata.roots);
  const gitDirectories = new Set(metadata.directory ? [metadata.directory] : []);
  const reads = new Set();
  const writableRoots = writableReferenceRoots(cwd, home);
  for (const reference of references(cwd, agentDir, home)) {
    const path = existingDirectory(reference.path);
    if (needsGitSockets && path !== undefined) {
      const directory = gitMetadata(path, home).directory;
      if (directory) gitDirectories.add(directory);
    }
    if (path === undefined) continue;
    const destinations = writableRoots.some((root) => within(path, root)) ? grants : reads;
    destinations.add(path);
  }
  // Stow links extension resources into the repo; only grant their actual targets.
  for (const path of [agentDir, join(home, ".agents", "skills"), join(home, ".cache", "pi")]) {
    const canonical = existingDirectory(path);
    if (canonical !== undefined) grants.add(canonical);
  }
  const configHome = environment.XDG_CONFIG_HOME || join(home, ".config");
  const dataHome = environment.XDG_DATA_HOME || join(home, ".local", "share");
  const cacheHome = environment.XDG_CACHE_HOME || join(home, ".cache");
  const extra = [...sshClientArguments(home, environment), ...serviceSocketArguments(cwd, home, environment, ipcRestricted)];
  extra.push(...endpointArguments(capabilities, { "selected-git-metadata": [...gitDirectories] }));
  const socketVariables = new Set(Object.values(capabilities).filter(capability => capability.backend === "json-lines").map(capability => capability.socketEnvironment));
  if (!ipcRestricted && environment.HERDR_ENV === "1") socketVariables.add("HERDR_SOCKET_PATH");
  if (ipcRestricted && environment.HERDR_ENV === "1" && environment.HERDR_SOCKET_PATH && !socketVariables.has("HERDR_SOCKET_PATH")) throw new Error("Herdr reporting is not enabled in the IPC capability profile");
  for (const variable of socketVariables) {
    const socket = environment[variable];
    if (!socket) continue;
    if (!isAbsolute(socket)) throw new Error(`${variable} must be an absolute socket path`);
    if (!statSync(socket).isSocket()) throw new Error(`${variable} must point to a socket`);
    extra.push("--allow-unix-socket", socket);
  }
  const editorSocket = environment.PI_NVIM_ASK_SOCKET;
  if (environment.PI_NVIM_SOCKET && !editorSocket) throw new Error("Native Neovim RPC is not a Pi Ask endpoint; update both Pi Ask integrations");
  if (editorSocket) {
    if (!isAbsolute(editorSocket)) throw new Error("PI_NVIM_ASK_SOCKET must be an absolute socket path");
    if (!statSync(editorSocket).isSocket()) throw new Error("PI_NVIM_ASK_SOCKET must point to a socket");
    extra.push("--allow-unix-socket", editorSocket);
  }
  for (const path of [
    join(home, ".pi-lens"),
    environment.PI_HASHLINE_DIR || join(configHome, "pi-hashline-edit-pro"),
    environment.FFF_FRECENCY_DB || join(cacheHome, "nvim", "fff_nvim"),
    environment.FFF_HISTORY_DB || join(dataHome, "nvim", "fff_queries"),
  ]) {
    if (existingDirectory(path) !== undefined) extra.push("--allow", path);
  }
  for (const path of [join(configHome, "fbb", "data", "typos.abolish"), join(configHome, "nix", "git", "config")]) {
    if (existingFile(path)) extra.push("--read-file", path);
  }
  const direnvAllow = existingDirectory(join(dataHome, "direnv", "allow"));
  // Approval is user-owned authorization; the sandbox may only consume existing decisions.
  if (direnvAllow !== undefined) reads.add(direnvAllow);
  // Keep legacy behavior until the candidate passes the Linux development/desktop gates.
  if (!ipcRestricted && environment.XDG_RUNTIME_DIR) {
    const runtime = existingDirectory(environment.XDG_RUNTIME_DIR);
    if (runtime === undefined) {
      console.warn(`pi sandbox launch: XDG_RUNTIME_DIR is missing (${JSON.stringify(environment.XDG_RUNTIME_DIR)}); continuing without runtime-directory access.`);
    } else {
      extra.push(...runtimeDirectoryArguments(runtime, platform));
    }
  }
  const args = [
    "run", "--profile", profile, "--allow-cwd", "--suppress-save-prompt", "/",
    ...(platform === "darwin" ? ["--trust-proxy-ca"] : []),
    // SSH bypasses the HTTP proxy; Linux also permits raw web clients with Landlock.
    ...(platform === "linux" ? ["--allow-connect-port", "22", "--allow-connect-port", "80", "--allow-connect-port", "443"] : []),
    ...extra,
    ...[...reads].filter((path) => !grants.has(path)).flatMap((path) => ["--read", path]),
    ...[...grants].flatMap((path) => ["--allow", path]),
    "--", ...sandboxRuntimeCommand(home, rawPi, envBinary),
  ];
  if ([...socketVariables].some(variable => Boolean(environment[variable])) || environment.PI_NVIM_ASK_SOCKET || environment.AGENT_BROWSER_SOCKET_DIR) {
    assertPrivateIpcGrants(args, cwd, home);
  }
  assertReadOnlySshGrants(args, cwd);
  const guardEnvironment = { ...environment, TMPDIR: environment.TMPDIR || tmpdir() };
  const loadedProfile = readJson(profile, "nono profile");
  assertCredentialSourceGrants(args, cwd, home, guardEnvironment, loadedProfile);
  assertRuntimeSecretGrants(args, cwd, home, guardEnvironment, loadedProfile, platform);
  return args;
}

export function prepareJitiCache(temporaryDirectory = tmpdir(), platform = process.platform) {
  // Landlock grants bind existing paths; create the cache before nono resolves the profile.
  if (platform === "linux") mkdirSync(join(temporaryDirectory, "jiti"), { recursive: true, mode: 0o700 });
}

export function prepareNpmCache(home = homedir()) {
  // Like Jiti's cache, these narrow profile paths must exist before Landlock grants are built.
  for (const directory of ["_cacache", "_logs"]) {
    mkdirSync(join(home, ".npm", directory), { recursive: true, mode: 0o700 });
  }
}

export function launchCommand(args, cwd, agentDir, home, environment, nono, rawPi, profile, envBinary, registry = defaultCapabilities) {
  if (!isAbsolute(rawPi) || !existsSync(rawPi)) throw new Error(`Raw Pi executable missing: ${rawPi}`);
  if (args[0] === "--no-sandbox") return [rawPi, ...args.slice(1)];
  if (!isAbsolute(nono) || !existsSync(nono)) throw new Error(`nono executable missing: ${nono}`);
  return [nono, ...launchArguments(cwd, agentDir, home, environment, profile, rawPi, envBinary, process.platform, registry), ...args];
}

export function loadProjectEnvironment(cwd, environment, direnv, run = spawnSync) {
  const envrc = join(cwd, ".envrc");
  let entry;
  try {
    entry = statSync(envrc);
  } catch (error) {
    if (error.code === "ENOENT") return { ...environment };
    throw error;
  }
  if (!entry.isFile()) throw new Error("Project .envrc must be a file");
  if (!isAbsolute(direnv) || !existsSync(direnv) || !statSync(direnv).isFile()) {
    throw new Error("Packaged direnv executable missing");
  }

  // Collect the diff before confinement; the launcher falls back to the sanitized inherited environment on failure.
  // Caller-controlled shell/Node preloads must not execute in this trusted bootstrap.
  const loaderEnvironment = { ...environment };
  for (const name of ["BASH_ENV", "ENV", "NODE_OPTIONS", "NODE_PATH"]) delete loaderEnvironment[name];
  const result = run(direnv, ["export", "json"], {
    cwd,
    env: loaderEnvironment,
    encoding: "utf8",
    timeout: 120_000,
    maxBuffer: 16 * 1024 * 1024,
  });
  // Direnv can exit zero after evaluation errors; inspect severity and shell diagnostics, not keywords.
  const diagnostics = stripVTControlCharacters(result.stderr || "");
  if (result.error || result.status !== 0 ||
      /^[ \t]*(?:(?:direnv|nix|devenv):[ \t]*)?(?:error|fatal)(?:[ \t:]|$)/im.test(diagnostics) ||
      /^[^:\r\n]+:[ \t]*(?:line[ \t]+)?\d+:(?![ \t]*warning(?:[ \t:]|$))/im.test(diagnostics)) {
    throw new Error("Project direnv environment load failed");
  }

  let exported;
  try {
    exported = result.stdout.trim() === "" ? {} : JSON.parse(result.stdout);
  } catch {
    throw new Error("Project direnv export is not valid JSON");
  }
  if (!record(exported)) throw new Error("Project direnv export must be an object");

  const loaded = { ...environment };
  for (const [name, value] of Object.entries(exported)) {
    if (value === null) delete loaded[name];
    else if (typeof value === "string") loaded[name] = value;
    else throw new Error("Project direnv export contains an invalid environment value");
  }
  delete loaded.NODE_OPTIONS;
  delete loaded.NODE_PATH;
  return loaded;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [nono, rawPi, profile, direnv, envBinary, ...args] = process.argv.slice(2);
    // Capture the binary wrapper's manifest before mutable project environment loading.
    const registry = loadCapabilities(process.env.PI_IPC_MANIFEST || undefined);
    let environment = { ...process.env };
    // No mutable JS preload or module path may run in this pre-sandbox process.
    delete environment.NODE_OPTIONS;
    delete environment.NODE_PATH;
    const entryBin = (environment.PATH || "").split(delimiter)[0];
    const home = homedir();
    const inheritedHome = environment.HOME;
    const inheritedEnvironment = { ...environment };
    const safeEnvironment = credentialEnvironmentForDirenv(environment);
    try {
      environment = loadProjectEnvironment(process.cwd(), safeEnvironment, direnv);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      console.error(`pi sandbox launch: ${message}; continuing without project direnv environment`);
      environment = safeEnvironment;
    }
    environment = prepareCredentialEnvironment(inheritedEnvironment, environment, home);
    if (inheritedHome === undefined) delete environment.HOME;
    else environment.HOME = inheritedHome;
    if (process.platform === "darwin" && !environment.XDG_RUNTIME_DIR) {
      environment.XDG_RUNTIME_DIR = environment.TMPDIR || tmpdir();
    }
    const configuredAgent = environment.PI_CODING_AGENT_DIR || join(home, ".pi", "agent");
    const agentDir = resolve(configuredAgent === "~" ? home : configuredAgent.startsWith("~/") ? join(home, configuredAgent.slice(2)) : configuredAgent);
    environment.PI_CODING_AGENT_DIR = agentDir;
    const managedBin = join(agentDir, "bin");
    const legacyBins = new Set([
      managedBin,
      join(home, ".pi", "agent", "bin"),
      join(home, "dotfiles", ".pi", "agent", "bin"),
    ]);
    const pathEntries = (environment.PATH || "").split(delimiter).filter(Boolean);
    // Keep Pi's managed bin present at the end so getShellEnv cannot prepend it.
    // The binary entry has already placed its immutable bin first.
    environment.PATH = [
      ...(entryBin ? [entryBin] : []),
      ...pathEntries.filter((path) => path !== entryBin && !legacyBins.has(resolve(path))),
      ...new Set(pathEntries.filter((path) => legacyBins.has(resolve(path)) && resolve(path) !== managedBin)),
      managedBin,
    ].join(delimiter);
    if (args[0] !== "--no-sandbox") prepareSandboxRuntime(home);
    const runPi = async (boundEnvironment) => {
      environment = boundEnvironment;
      const command = launchCommand(args, process.cwd(), agentDir, home, environment, nono, rawPi, profile, envBinary, registry);
      // Herdr must identify the host-visible bootstrap even when nono hides the child process.
      process.title = "pi";
      const run = (selectedProfile) => {
        if (command[0] === nono) command[command.indexOf("--profile") + 1] = selectedProfile;
        return spawnSync(command[0], command.slice(1), { stdio: "inherit", env: environment });
      };
      if (command[0] === nono) {
        // Herdr sees the foreground nono wrapper, not Pi's isolated process group.
        if (environment.HERDR_ENV === "1") environment.HERDR_AGENT = "pi";
        prepareJitiCache();
        prepareNpmCache();
        return withProtectedShellProfile(profile, home, environment, run);
      }
      return runWithCredentialProxy(nono, profile, command, environment);
    };
    const ipcRestricted = readJson(profile, "nono profile")?.linux?.af_unix_mediation === "pathname";
    const runWithCapabilities = bound => withIpcCapabilities(bound, inheritedEnvironment, home, process.cwd(), agentDir, args, registry, ipcRestricted ? "restricted" : "ordinary", runPi);
    const child = ipcRestricted
      ? await withSessionServiceEnvironment(environment, home, runWithCapabilities)
      : await runWithCapabilities(environment);
    if (child.error) throw child.error;
    if (child.signal) process.kill(process.pid, child.signal);
    process.exit(child.status ?? 1);
  } catch (error) {
    console.error(`pi sandbox launch: ${error instanceof Error ? error.message : String(error)}`);
    process.exit(1);
  }
}
