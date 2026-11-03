# Pi sandbox (nono)

Host-side launcher, credential boundary and IPC brokers that confine Pi under nono. This code is a security boundary: a refactor that changes a grant, a guard, or their order changes what an agent can reach.

## Layout

`scripts/` is grouped by responsibility. Fallow enforces the import direction in `.fallowrc.json`:

- `launcher.mts`, `pi-desktop.mts`: process entry points used by the Nix wrappers.
- `launch/`: builds one session's command line (`plan.mts`), and handles references, Git metadata, the environment and runtime directories.
- `protection/`: read-only protection for Pi controls and shell startup files.
- `credentials/`: credential declarations, the proxy, the store, and grant checks.
- `model-executor/`: host-side model process for a session.
- `ipc/`: capability policy, private IPC state and the filter helper. Each JSON-lines provider (`herdr/provider.mts`, `desktop/provider.mts`, `ipc/inherited-socket.mts`) implements `IpcProvider` (`ipc/provider.mts`): `start` in the launcher, `serve` in the helper. Register a new provider in `ipc/providers.mts` and the manifest schema's `provider` enum; providers receive `startHelper` through the session and must not import `ipc/helper-launch.mts`.
- `shared/`: dependency-free path and JSON helpers. Add to this directory only when two or more domains need a helper.

## Rules

- Fail closed. Never add a fallback that runs without a guard, a broker or the sandbox when validation fails.
- Linux Landlock cannot subtract a protected child from a writable parent. Grants are split instead (`launch/plan.mts`). Do not replace a split grant with a broad `--allow`.
- Grants are decisions in a `GrantPlan` (`shared/grant-plan.mts`): builders return `Grant` entries, every launch guard inspects the plan, and `toArguments` turns it into nono flags once. Do not add a guard or builder that reads or produces nono argv directly. Grant order is argument order.
- Read the nono profile only through `readNonoProfile` (`shared/nono-profile.mts`), so every module sees the same shape checks and errors.
- Paths below are read by Nix or spawned by file URL, not imported. When you move one, update its consumer and the `entry` list in `.fallowrc.json`:
  - `credentials/credentials.json`: read by `lib/pi-credential-profile.nix`, `modules/sops.nix` and `default.nix`.
  - `credentials/claude-credential.mts`: resolved through the `script` field in `credentials.json`.
  - `ipc/capabilities.json`, `ipc/policy.mts`, `launcher.mts`, `pi-desktop.mts` and `pi-ask.lua`: used by `../pi/default.nix`.
  - `shared/sandbox-policy.json` and `shared/sandbox-policy.mts`: the defaults of the `pi.sandbox` option in `../pi/sandbox.nix`, and its build-time validation in `../pi/default.nix`.
  - `ipc/helper.mts`, `model-executor/server.mts` and `launch/diagnostics-extension.mts`: spawned or loaded by URL.
- Import from the module that owns a function. Do not re-export it through `launcher.mts`.
- Tests stay in `__tests__/`: the `nono-tests` check runs every `*.test.mjs` file there, so a new file needs no Nix change. A test that needs a tool reads it from a `*_TEST_BINARY` variable and skips itself when the variable is unset; add the variable to `nonoSuite` in `../pi/default.nix`.

## Sandbox policy

- Tool grants, extra agent paths, the Pi agent layout, shell startup files, SSH public files, configuration repositories and `XDG_RUNTIME_DIR` entries are data in `shared/sandbox-policy.json`, not code. Change shipped defaults there. From another module, use the `pi.sandbox` option: add a named grant, set `pi.sandbox.filesystem.grants.<name>.enable = false`, or append to a list.
- The launcher file uses the same names and nesting as `pi.sandbox`, without `ipc`, and with disabled grants removed. Grants apply in name order; order carries no meaning.
- `pi.sandbox.exceptions.configurationRepositories` cannot be appended to from another module; replacing it requires `mkForce`, because it grants write access to Pi configuration.
- The code keeps the rules: existence checks, symlink and hard-link checks, Git worktree validation and grant splitting. Do not move a rule into the file.
- `shared/sandbox-policy.schema.json` is part of the security boundary. SSH client files must stay public files, because each one also bypasses the `~/.ssh` deny rule. Paths stay relative to their base, with no `..` segments.
- A project `.envrc` must never choose a grant. `sessionEnvironment` (`launch/environment.mts`) restores every variable in `hostOnlyVariables` to the launcher's own value, or removes it. A new variable that selects a socket, directory or file grant belongs in that list, with a case in `__tests__/launch-environment.test.mjs`.
- Tool grant locations also read XDG_CONFIG/CACHE/DATA_HOME from the environment the launcher started with (`hostEnvironment` in `launch/plan.mts`). Those three stay project-settable for Pi itself.

## TypeScript

- Node runs the `.mts` sources directly through type stripping; there is no build step. Use only erasable syntax: no enums, namespaces or parameter properties. Relative imports keep the `.mts` extension.
- `typescript` and `@types/node` are devDependencies for local editing. The Nix runtime strips them, and the Nix type check uses `pkgs.typescript_7`; keep both on the same TypeScript version.
- Do not use `any`. Before every `as unknown as T`, add a `// SAFETY:` comment that states the invariant.
- Shared types live in `shared/types.mts`. Define a domain type in the module that owns it, for example capability types in `ipc/policy.mts`.

## Effect

- Grant planning and its guards return `Effect.Effect<A, SandboxError>`. The four error classes in `shared/errors.mts` are the only expected failures; anything else is a defect.
- Import Effect modules by subpath, for example `import * as Effect from "effect/Effect"`. The root `effect` import loads the whole library and adds about 150 ms to every `pi` launch.
- Wrap synchronous policy code that throws with `attempt()`. Keep a module's internal helpers synchronous and export the Effect wrapper.
- Keep every step in its original order; grant order is part of the security contract. Use `yield*` for each step rather than combining steps in parallel.
- Run an Effect at a synchronous boundary with `runSyncOrThrow()`, which rethrows the original error.
- Session resources (helper processes, the model executor, diagnostics, browser state, the macOS profile, the credential proxy) are scoped: each returns `Effect<…, …, Scope>` and is released when `launcher.mts` closes its scope. Register cleanup with `acquireRelease` right after creating the resource, before waiting for readiness; a failed acquire never runs its release.
- `launcher.mts` acquires resources in the order services, IPC helpers, model executor, diagnostics, profile; they are released in reverse. Keep that order.
- Helper processes use `scopedHelper()` in `ipc/private.mts`. Do not add another stdin-close, SIGTERM, SIGKILL sequence.
- `HostProcessError` covers helper processes; it is not a `SandboxError`, because policy checks never raise it.
- Tests run a scoped resource around a callback with `withScoped` or `withScopedSync` from `__tests__/fixtures/scoped.mjs`.
- Filesystem access stays on `node:fs`. Add an Effect service only when a test needs to replace the filesystem.

## Checks

- Run `npx tsc -p .` from this directory; it must report no errors. Nix runs the same check as `checks.<system>.nono-typecheck`.
- Run `fallow dead-code .`, `fallow architecture .` and `fallow dupes .` from this directory. All three should report no issues.
- `node --test __tests__/*.test.mjs` runs on macOS, but tests that need Unix sockets, native nono or the Nix daemon fail inside a sandboxed agent session. Compare per-test results with a run on the unchanged tree; the total is not a meaningful signal.
- The real enforcement checks are the `x86_64-linux` checks listed under Verification in `docs/agents/pi-sandbox-policy.md` (`nono-tests`, `nono-tests-ordinary` and the NixOS VM test). Run them on an x86_64-linux host before activation.

## References

- Read before changing grants, credentials or network policy: `docs/agents/pi-sandbox-policy.md`
- Read before adding or changing an IPC capability: `docs/agents/pi-ipc-capabilities.md`
