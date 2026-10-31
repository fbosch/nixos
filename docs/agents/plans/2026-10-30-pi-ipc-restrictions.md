# Pi IPC restrictions

Status: partial implementation, not deployed. `packages.<system>.pi-ipc-candidate` selects the restricted policy. The installed system package remains the ordinary launcher. Do not promote the candidate until the remaining workflow and platform checks pass.

The [capability registry guide](../pi-ipc-capabilities.md) describes the subsequent shared-runtime implementation. Its native Git fsmonitor probe fails inside nono and remains a rollout blocker. The test counts below record the earlier adapter slice.

## Implemented slices

The Nix-owned launcher and profile remain under `modules/development/ai/nono/`. The initial adapter slice left dependencies unchanged. The subsequent registry implementation adds a feature-local Ajv dependency and npm lockfile. Flake input pins remain unchanged.

- `lib/pi-credential-profile.nix` prepares `af_unix_mediation = "pathname"` with `sandbox_policy = "landlock"` for the candidate. The ordinary profile retains `off` and the broad runtime-directory grant. This is an explicit rollout gate, not a fallback after enforcement failure.
- The candidate replaces the runtime-root grant with the selected devenv runtime and direct-child socket-directory grants. Existing project service directories receive nonrecursive grants. The exact Nix daemon endpoint, selected SSH agent and discovered Git fsmonitor endpoints remain permitted.
- `service-ipc.mjs` derives the devenv 2.4 runtime from the canonical selected dotfile path, including exported profile paths. `DEVENV_RUNTIME` is an output, not an override. Each candidate launch creates a private `AGENT_BROWSER_SOCKET_DIR`, disables automatic incumbent-browser attachment and sets `PI_LENS_WARM_ATTACH=0`.
- `pi-ask.lua` implements a dedicated NDJSON endpoint. The Neovim launcher captures an immutable Nix-store factory and its callbacks before launching Pi. Bind, prompt, acknowledgment and closure messages retain launch/session identity, canonical worktree checks, payload limits and stale-buffer handling. No message supplies a native RPC method, executable code or arbitrary file operation.
- `herdr-bootstrap.mjs`, `herdr-protocol.mts`, `herdr-reader.mjs` and `herdr-server.mts` implement candidate-only reporting and passive workspace reads. The helper captures pane identity and the upstream socket from the inherited environment, not direnv. It starts before nono resolves socket grants and receives no inherited environment or unrelated descriptors.
- Herdr reporting permits `pane.report_agent`, `pane.report_agent_session`, `pane.report_metadata` and `pane.release_agent` for the launching pane only. It checks source/agent identity, state fields, session-reference shapes and session-directory membership. Metadata is limited to `pi_session_title`. Unknown fields, `resume_argv`, other-pane reporting and terminal-control methods fail. Shutdown drains accepted reports before releasing reporting state.
- Herdr additionally allows `ping`, `pane.list` and passive `pane.read` snapshots within the captured launch workspace. Reads default to 120 lines, allow at most 200 lines, strip terminal controls and enforce a 64 KiB frame bound. Request and response workspace checks prevent cross-workspace disclosure. The user accepts secrets visible in permitted panes; execution, prompting, scrolling and pane input remain blocked.
- The pinned generated Herdr reporter has a behavioral compatibility test against the same restricted endpoint. Custom clients and the generated reporter therefore use the same endpoint authority. Existing OSC 7 CWD reporting remains unchanged.

The new Neovim integration and its Nix module must move together. Pi Ask resolves the packaged helper from `/run/current-system/sw/share/pi/pi-ask.lua` at launch and validates its canonical, read-only Nix-store target. It does not load host code from a writable checkout. Native Neovim RPC is not a compatibility path.

## Verified on rvn-mac

These results use installed nono 0.80.0 and the current working-tree launcher. They do not establish Linux enforcement or successful deployment of the complete Nix package.

- The focused Node suite passed 81 tests and skipped 12. It covers launcher policy, reporting validation, private endpoint lifecycle, generated-reporter compatibility, credential-proxy lifecycle and the production Pi Ask helper.
- An actual-launcher macOS test exchanged typed Pi Ask messages with a real Neovim process and delivered Herdr reports through the restricted helper. Direct connections to both native Neovim endpoints, the raw Herdr endpoint and unrelated sockets failed. Relative paths, socket symlinks and directory-symlink aliases also failed.
- The Bun suite passed 27 tests across seven files. This includes 19 Pi Ask tests for Unicode prompts/selections, acknowledgment, closure, replacement sessions, disconnection and immediate reopen with stale events. Herdr tests cover standalone/embedded reporter selection, prompt state, session names and CWD restoration.
- Four headless Neovim tests passed: `pi_launcher.lua`, `pi_session_restore.lua`, `pi_prompt_context.lua` and `pi_prompt_owner.lua`.
- Nix parsing, JavaScript/TypeScript syntax checks and `git diff --check` passed. The candidate derivation evaluated from a filtered snapshot containing untracked working-tree files.

The browser branch of `ipc-workflows.test.mjs` requires `AGENT_BROWSER_TEST_BINARY` and `LIGHTPANDA_TEST_BINARY`; it was skipped in the passing focused run. An earlier real browser attempt failed startup with permission errors. Successful socket setup is not evidence that Lightpanda works.

## Verified on rvn-pc

These results use nono 0.80.0 on Linux with Landlock. They cover Nix checks and package builds, not interactive workflows under the candidate.

- `pi-ipc-candidate`, `pi-sandbox` and the `rvn-pc` system build. The candidate wrapper's launcher suite passed 182 tests and skipped 26.
- `nono-pi-socket-isolation-restricted` runs the socket-isolation suite against the candidate profile with `af_unix_mediation = "pathname"`. The selected SSH-agent and Pi Ask endpoints connected and the browser IPC directory accepted a bind. Wayland, Podman, Docker, systemd, session-bus, native Neovim, workdir, temporary, Pi-state and nested browser sockets were denied, including socket and directory symlink aliases and relative paths.
- `pi-ipc`, `pi-launcher-routing`, `nono-pi-socket-isolation`, `nono-pi-credential-filesystem`, `nono-pi-ssh-access`, `nono-pi-git-worktree`, `nono-pi-github-access`, `nono-pi-azure-access` and `nono-pi-nix-build-access` pass. Except for the restricted socket check, these use the ordinary profile.
- In a live ordinary session, sops-nix user secrets under `$XDG_RUNTIME_DIR/secrets.d` could not be opened from the sandbox. A `systemd-run --user` process opened them, which the candidate's pathname mediation is meant to prevent.

### Interactive gate probes (2026-10-31)

The same probe script ran once in an ordinary session and once in a `pi-ipc-candidate` session, both launched from Herdr on rvn-pc. The host SSH agent held no identities, so rows 8 and 10 do not test the candidate.

| # | Probe | Ordinary | Candidate |
|---:|---|---|---|
| 1 | Open `secrets.d/age-keys.txt` | denied | denied |
| 2 | `systemd-run --user --wait --pipe true` | runs on the host | denied: user bus `Operation not permitted` |
| 3 | Podman API `_ping` | ok | denied (curl exit 7) |
| 4 | `hyprctl version` | ok | denied (exit 4) |
| 5 | `busctl --user list` | ok | denied: `Operation not permitted` |
| 6 | `wezterm cli list` | ok | denied (exit 1) |
| 7 | `ssh-add -l` | agent reachable, no identities | agent reachable, no identities |
| 8 | `ssh rvn-srv true` | fails: no agent identity | fails: no agent identity |
| 9 | `git ls-remote origin HEAD` | ok | ok; libsecret logs `store failed: Could not connect: Permission denied` |
| 10 | `ssh-keygen -Y sign` | fails: no agent identity | fails: no agent identity |
| 11 | `nix build nixpkgs#hello` | ok | ok |
| 12 | `devenv shell -- true` | fails: `opening file "/": Permission denied` | fails: `Failed to build eval state` |
| 13 | `grim` 10×10 capture | fails: `failed to create buffer` | fails: `failed to create display` |
| 14 | `agent-browser open about:blank` | fails: Lightpanda port bind `EACCES` | same |

Pi-Lens returned no diagnostics for `launcher.mjs` in the candidate session and reported no error, so local-mode diagnostic execution remains unconfirmed.

Follow-up changes after these probes:

- Both Linux profiles now grant `/dev/shm`. `grim` allocates its buffer with `shm_open`, and Landlock denied `/dev/shm/grim-*`. The user approved the candidate grant, including access to unrelated same-user shared-memory objects. Fresh ordinary and candidate sandbox probes using the rebuilt launcher arguments each produced a valid 10×10 PNG. The probes disabled networking and credential capture in temporary profile copies.
- devenv's embedded Nix opens `/` with `O_RDONLY`, which Landlock denies without a recursive read grant on `/`. An `O_PATH` handle would suffice, but a local patch rebuilds Nix and devenv from source and was rejected. The launcher loads the devenv environment before confinement; `devenv up`, `devenv shell` and reloads after editing `devenv.nix` run outside Pi.
- The user approved direct Wayland socket access in the candidate, including clipboard reads and broader compositor authority. The launcher grants only the inherited compositor socket, captured before project environment loading, and no longer forces OSC 52. `wl-copy`, `wl-paste` and Pi's native copy can use this socket. Both profiles also grant `/dev/shm` for native screenshots; `pi-desktop screenshot` retains its broker path. Other host IPC restrictions remain unchanged.
- Interactive launches run `ssh-add ~/.ssh/id_ed25519` on the host when the inherited agent is empty, so SSH and commit signing work inside both profiles without exposing the private key file. Non-interactive launches, missing keys and unreachable agents skip it.

- Wayland follow-up validation passed: `pi-launcher-routing`, `pi-ipc`, both socket-isolation checks and `pi-ipc-candidate` build. The launcher suite passed 195 tests and skipped 26. The restricted socket probe connects to the selected display while rejecting a second display and unrelated IPC endpoints. A direct source test could not resolve Ajv; the Nix runtime supplies the pinned dependencies and its suite passed.
- Native screenshot follow-up validation passed: `pi-launcher-routing`, `pi-ipc`, both socket-isolation checks, and ordinary/candidate launcher builds. The candidate probe still denied unrelated sockets. Syntax checks, `git diff --check` and the focused prose check passed. LSP checks for the two changed JavaScript files were inconclusive because their language server is disabled. The temporary screenshot files and host pane were removed; installed launchers and existing sessions were not changed.
- After the user rebuilt and activated, the restarted neighbouring candidate on rvn-pc confirmed `--allow /dev/shm` in its own nono launch. Direct `grim -g '0,0 10x10'` exited 0 and produced a PNG with a valid signature, valid IHDR and 10×10 dimensions. The temporary capture file and directory were removed.

### Workspace pane-read follow-up

- `pi-ipc` passes 72 tests, including the pinned native Herdr CLI reading through the broker and rejecting input. The launcher suite passes 207 tests and skips 26. `pi-launcher-routing`, restricted socket isolation, `pi-ipc-candidate` and `pi-sandbox` build from the working tree.
- A broker from the immutable runtime successfully listed the two panes in the real launch workspace and read the neighboring pane through native `herdr pane read`. Other-workspace listing, agent prompting and pane-input requests returned `PI_IPC_DENIED`. The probes used a nonexistent target for every control operation.
- The initial live broker check ran in the ordinary session; a nested candidate could not initialize its credential proxy because the outer sandbox denied an ephemeral loopback bind. After the user rebuilt and restarted the neighboring candidate, native listing returned only `w1F:p1` and `w1F:pN`. Both `visible` and `recent-unwrapped` reads of `w1F:p1` succeeded with 2,113 bytes / 10 lines and no terminal escapes. Cross-workspace listing/reading, CLI command execution, prompting and pane-input requests returned `PI_IPC_DENIED`. Direct access to the real Herdr socket failed with `EACCES`. Fresh-candidate pane-read verification passed; no permissions were broadened.
- Active LSP probes for the changed implementation files were unconfirmed because the configured servers were disabled. The explicit Nix tests and package builds supply validation; no LSP-clean claim is made.

## Remaining rollout blockers

- Interactive rollout coverage remains partial. In a later candidate session, SSH authentication to `rvn-srv`, agent-backed signing/verification and a broker-produced 10×10 PNG passed. The user confirmed native clipboard copy/paste and image paste. A fresh ordinary-profile `grim` capture remains unverified. devenv and agent-browser retain their documented baseline failures.
- Lightpanda startup remains unresolved. Its ephemeral loopback TCP connections need a passing real-browser test without unrelated network-policy changes. On rvn-pc the ordinary profile fails too: agent-browser binds `127.0.0.1:0` to pick a Lightpanda port, and Landlock returns `EACCES` because only the profile's `open_port` entries may bind.
- The candidate retains the `desktop` broker alongside direct Wayland access. Broker screenshot capture passed in a live candidate session, and the user confirmed native clipboard use. The bounded Hyprland diagnostics/window/layer adapter and session-produced image opening remain unimplemented. Direct Wayland protocols retain broader desktop authority.
- A scoped replacement for Linux `git-credential-libsecret` access is not implemented. Do not restore unrestricted session-bus access to make HTTPS credentials work.
- Explicit host-container management and deliberate existing Chrome/Firefox attachment capabilities are not implemented. Clearing inherited auto-attach settings does not prevent an intentional TCP connection by native code.
- Pi-Lens execution is confirmed: an active LSP probe detected the deliberate TS2322 in the candidate. After correction, the push-only server reported no diagnostics but could not confirm a clean check. That clean-status limitation remains inconclusive. Warm-attach startup and memory costs have not been measured.
- Earlier wider Git worktree and SSH runtime probes failed because their fixtures requested proxy-CA trust without a proxy feature. Those failures were not treated as compatibility passes or fixed by broadening IPC permissions.
- The complete SDK typecheck remains blocked by diagnostics in unchanged `just`, `prompt-ui` and `subagents` code. Passing Bun execution is not a complete typecheck.
- Complete Herdr UI restoration under the candidate remains unverified.

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
