# Pi sandbox (nono)

Host-side launcher, credential boundary and IPC brokers that confine Pi under nono. This code is a security boundary: a refactor that changes a grant, a guard, or their order changes what an agent can reach.

## Layout

`scripts/` is grouped by responsibility. Fallow enforces the import direction in `.fallowrc.json`:

- `launcher.mts`, `pi-desktop.mts`: process entry points used by the Nix wrappers.
- `launch/`: builds one session's command line (`plan.mts`), and handles references, Git metadata, the environment and runtime directories.
- `protection/`: read-only protection for Pi controls and shell startup files.
- `credentials/`: credential declarations, the proxy, the store, and grant checks.
- `model-executor/`: host-side model process for a session.
- `ipc/`: capability policy, private IPC state and the filter helper. `herdr/` and `desktop/` are its providers.
- `shared/`: dependency-free path and JSON helpers. Add to this directory only when two or more domains need a helper.

## Rules

- Fail closed. Never add a fallback that runs without a guard, a broker or the sandbox when validation fails.
- Linux Landlock cannot subtract a protected child from a writable parent. Grants are split instead (`launch/plan.mts`). Do not replace a split grant with a broad `--allow`.
- Paths below are read by Nix or spawned by file URL, not imported. When you move one, update its consumer and the `entry` list in `.fallowrc.json`:
  - `credentials/credentials.json`: read by `lib/pi-credential-profile.nix`, `modules/sops.nix` and `default.nix`.
  - `credentials/claude-credential.mts`: resolved through the `script` field in `credentials.json`.
  - `ipc/capabilities.json`, `ipc/policy.mts`, `launcher.mts`, `pi-desktop.mts` and `pi-ask.lua`: used by `../pi/default.nix`.
  - `ipc/helper.mts`, `model-executor/server.mts` and `launch/diagnostics-extension.mts`: spawned or loaded by URL.
- Import from the module that owns a function. Do not re-export it through `launcher.mts`.
- Tests stay in `__tests__/`, because Nix checks reference them there.

## TypeScript

- Node runs the `.mts` sources directly through type stripping; there is no build step. Use only erasable syntax: no enums, namespaces or parameter properties. Relative imports keep the `.mts` extension.
- `typescript` and `@types/node` are devDependencies for local editing. The Nix runtime strips them, and the Nix type check uses `pkgs.typescript_7`; keep both on the same TypeScript version.
- Do not use `any`. Before every `as unknown as T`, add a `// SAFETY:` comment that states the invariant.
- Shared types live in `shared/types.mts`. Define a domain type in the module that owns it, for example capability types in `ipc/policy.mts`.

## Checks

- Run `npx tsc -p .` from this directory; it must report no errors. Nix runs the same check as `checks.<system>.nono-typecheck`.
- Run `fallow dead-code .`, `fallow architecture .` and `fallow dupes .` from this directory. All three should report no issues.
- `node --test __tests__/*.test.mjs` runs on macOS, but tests that need Unix sockets, native nono or the Nix daemon fail inside a sandboxed agent session. Compare per-test results with a run on the unchanged tree; the total is not a meaningful signal.
- The real enforcement checks are the `x86_64-linux` checks listed under Verification in `docs/agents/pi-sandbox-policy.md`. Run them on `rvn-pc` before activation.

## References

- Read before changing grants, credentials or network policy: `docs/agents/pi-sandbox-policy.md`
- Read before adding or changing an IPC capability: `docs/agents/pi-ipc-capabilities.md`
