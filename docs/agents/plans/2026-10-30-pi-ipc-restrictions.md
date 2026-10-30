# Pi IPC restrictions

Status: partial implementation, not deployed. `packages.<system>.pi-ipc-candidate` selects the restricted policy. The installed system package remains the ordinary launcher. Do not promote the candidate until the remaining workflow and platform checks pass.

The [capability registry guide](../pi-ipc-capabilities.md) describes the subsequent shared-runtime implementation. Its native Git fsmonitor probe fails inside nono and remains a rollout blocker. The test counts below record the earlier adapter slice.

## Implemented slices

The Nix-owned launcher and profile remain under `modules/development/ai/nono/`. The initial adapter slice left dependencies unchanged. The subsequent registry implementation adds a feature-local Ajv dependency and npm lockfile. Flake input pins remain unchanged.

- `lib/pi-credential-profile.nix` prepares `af_unix_mediation = "pathname"` with `sandbox_policy = "landlock"` for the candidate. The ordinary profile retains `off` and the broad runtime-directory grant. This is an explicit rollout gate, not a fallback after enforcement failure.
- The candidate replaces the runtime-root grant with the selected devenv runtime and direct-child socket-directory grants. Existing project service directories receive nonrecursive grants. The exact Nix daemon endpoint, selected SSH agent and discovered Git fsmonitor endpoints remain permitted.
- `service-ipc.mjs` derives the devenv 2.4 runtime from the canonical selected dotfile path, including exported profile paths. `DEVENV_RUNTIME` is an output, not an override. Each candidate launch creates a private `AGENT_BROWSER_SOCKET_DIR`, disables automatic incumbent-browser attachment and sets `PI_LENS_WARM_ATTACH=0`.
- `pi-ask.lua` implements a dedicated NDJSON endpoint. The Neovim launcher captures an immutable Nix-store factory and its callbacks before launching Pi. Bind, prompt, acknowledgment and closure messages retain launch/session identity, canonical worktree checks, payload limits and stale-buffer handling. No message supplies a native RPC method, executable code or arbitrary file operation.
- `herdr-bootstrap.mjs`, `herdr-protocol.mts` and `herdr-server.mts` implement candidate-only reporting. The helper captures pane identity and the upstream socket from the inherited environment, not direnv. It starts before nono resolves socket grants and receives no inherited environment or unrelated descriptors.
- Herdr validation permits only `pane.report_agent`, `pane.report_agent_session`, `pane.report_metadata` and `pane.release_agent`. It checks source/agent identity, state fields, session-reference shapes and session-directory membership. Metadata is limited to `pi_session_title`. Unknown fields, `resume_argv`, other-pane access and terminal-control methods fail. Shutdown drains accepted reports before releasing reporting state.
- The pinned generated Herdr reporter has a behavioral compatibility test against the same restricted endpoint. Custom clients and the generated reporter therefore use the same endpoint authority. Existing OSC 7 CWD reporting remains unchanged.

The new Neovim integration and its Nix module must move together. `PI_NVIM_ASK_HOST` must identify the Nix-owned helper, not a writable checkout. Native Neovim RPC is not a compatibility path.

## Verified on rvn-mac

These results use installed nono 0.80.0 and the current working-tree launcher. They do not establish Linux enforcement or successful deployment of the complete Nix package.

- The focused Node suite passed 81 tests and skipped 12. It covers launcher policy, reporting validation, private endpoint lifecycle, generated-reporter compatibility, credential-proxy lifecycle and the production Pi Ask helper.
- An actual-launcher macOS test exchanged typed Pi Ask messages with a real Neovim process and delivered Herdr reports through the restricted helper. Direct connections to both native Neovim endpoints, the raw Herdr endpoint and unrelated sockets failed. Relative paths, socket symlinks and directory-symlink aliases also failed.
- The Bun suite passed 27 tests across seven files. This includes 19 Pi Ask tests for Unicode prompts/selections, acknowledgment, closure, replacement sessions, disconnection and immediate reopen with stale events. Herdr tests cover standalone/embedded reporter selection, prompt state, session names and CWD restoration.
- Four headless Neovim tests passed: `pi_launcher.lua`, `pi_session_restore.lua`, `pi_prompt_context.lua` and `pi_prompt_owner.lua`.
- Nix parsing, JavaScript/TypeScript syntax checks and `git diff --check` passed. The candidate derivation evaluated from a filtered snapshot containing untracked working-tree files.

The browser branch of `ipc-workflows.test.mjs` requires `AGENT_BROWSER_TEST_BINARY` and `LIGHTPANDA_TEST_BINARY`; it was skipped in the passing focused run. An earlier real browser attempt failed startup with permission errors. Successful socket setup is not evidence that Lightpanda works.

## Remaining rollout blockers

- Linux runtime checks remain unavailable because remote access was declined. No Linux Nix build, Git signing/authentication, devenv service operation, LSP diagnostic or Hyprland workflow has passed under the candidate.
- Lightpanda startup remains unresolved. Its ephemeral loopback TCP connections need a passing real-browser test without unrelated network-policy changes.
- The bounded Hyprland diagnostics/window/layer/screenshot adapter, desktop-session environment resolution, `no_screen_share` enforcement, explicit clipboard transfers and session-produced image opening are not implemented.
- A scoped replacement for Linux `git-credential-libsecret` access is not implemented. Do not restore unrestricted session-bus access to make HTTPS credentials work.
- Explicit host-container management and deliberate existing Chrome/Firefox attachment capabilities are not implemented. Clearing inherited auto-attach settings does not prevent an intentional TCP connection by native code.
- Pi-Lens local mode is selected, but real diagnostic execution remains unverified. Disabling warm attach sacrifices shared-server startup and memory reuse; the performance cost has not been measured.
- Earlier wider Git worktree and SSH runtime probes failed because their fixtures requested proxy-CA trust without a proxy feature. Those failures were not treated as compatibility passes or fixed by broadening IPC permissions.
- The complete SDK typecheck remains blocked by diagnostics in unchanged `just`, `prompt-ui` and `subagents` code. Passing Bun execution is not a complete typecheck.
- The candidate package build did not complete. The offline build lacked cached dependencies and failed fetching `config.guess` because `cgit.git.savannah.gnu.org` did not resolve. Full Nix package checks and complete Herdr UI restoration remain unverified.

## Enforcement limits and remaining authority

The installed nono 0.80.0 derivation identifies its unpatched source as `/nix/store/5vpr2zqy9b8635cmwchc2y3i7x1iiq1l-source`. Review the pinned source again when changing nono or promoting the candidate.

- `crates/nono-cli/src/exec_strategy/supervisor_linux.rs` approves network notifications with seccomp `CONTINUE`. `read_notif_sockaddr` in `crates/nono/src/sandbox/linux.rs` documents the child-controlled address-mutation race. The typed adapters do not repair that race.
- The explicit Landlock policy selects `prepare_landlock_with_abi` rather than the `auto` policy's seccomp network baseline. Pathname mediation does not itself add an `io_uring_setup` prohibition. Do not infer the stronger baseline from the general networking documentation.
- `auto` selects a different syscall/network baseline, including restrictions relevant to direct TCP connections and io_uring. It was not adopted as an IPC compatibility fix.
- An allowed peer can pass an already-connected descriptor through `SCM_RIGHTS`. Endpoint grants authorize the peer's protocol; bind grants also authorize connecting. Brokers and pathname checks do not establish complete containment of hostile native code.
- The candidate retains powerful Nix daemon, selected SSH-agent, project-service and worktree access. SSH-agent access is signing authority, not read-only metadata. Inherited default-profile and runtime-group grants remain part of the effective policy.
- Existing direct-network exceptions and debugging-port policy remain unchanged. This work does not prove that TCP host services or remote MCP destinations are inaccessible.
- macOS results establish the exercised Seatbelt denials only. Linux pathname results cannot be inferred from them, and neither platform's negative probes prove all possible aliases or native-code bypasses are closed.

The ordinary Linux profile still has unrestricted Unix IPC mediation. The candidate reduces permitted operations in the tested integrations, but it is not ready to replace that profile by default.
