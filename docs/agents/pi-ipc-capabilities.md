# Pi IPC capabilities

The IPC registry configures selected-repository fsmonitor access and bounded JSON-lines filters. The Nix-owned Pi launcher selects the restricted profile by default on Linux and macOS. The user authorized promotion without completed macOS validation. The known native macOS fsmonitor failure remains unresolved.

## Configuration and ownership

The default manifest is `modules/development/ai/nono/scripts/ipc-capabilities.json`. The flake-parts option `piIpcRegistry` can supply a complete replacement manifest. Nix serializes the selected configuration into the store and builds a runtime with Ajv 8.20.0 and its locked dependencies.

The binary wrapper forces `PI_IPC_MANIFEST` to the store path. The launcher loads and validates that file before loading the project environment. Project environment changes cannot replace the captured registry, choose upstream sockets, or forge Herdr identity.

The manifest has a capability catalog and profile selections. A capability declaration alone does not enable it. The `ordinary` profile preserves the existing direct fsmonitor behavior on macOS. The `restricted` profile selects the bounded Herdr filter, the desktop broker and exact fsmonitor bind/connect grants on macOS and Linux.

The restricted Linux launcher also grants the exact inherited Wayland socket outside the registry. This is full compositor protocol access, including clipboard reads and any exposed screen-capture or input-injection protocols. It is not constrained by the desktop broker's operation schemas. The launcher captures the socket before project environment loading and exports its absolute path. It does not grant the runtime directory or force OSC 52. D-Bus, Hyprland control and other unselected sockets remain denied.

Both Linux profiles grant `/dev/shm` so native `grim` can allocate screenshot buffers. This also exposes unrelated same-user shared-memory objects; Hyprland does not control that namespace. The user explicitly accepted this access. `pi-desktop screenshot` remains available through the broker in the restricted launcher.

Malformed manifests, unknown capabilities or providers, invalid schemas, conflicting socket exports and missing required launch bindings fail startup. There is no direct-service fallback after filter failure. The ordinary Linux comparison profile still uses unrestricted Unix IPC mediation; selecting a filter there would not establish socket confinement.

## Supported mechanisms

| Backend | Declaration | Authority |
| --- | --- | --- |
| `endpoint` | `discovery = selected-git-metadata`, a socket filename, and a profile-specific access mode | Full protocol access to each selected endpoint |
| `json-lines` | A trusted endpoint provider, exported socket variable, operation schemas, context bindings, limits and cleanup messages | Only accepted messages; forwarding providers reply with acknowledgments, host-handled providers may return a result |

The endpoint backend resolves selected worktree, shared Git and explicitly referenced Git metadata directories. `connect-existing` grants existing user-owned, unaliased sockets. `bind` grants the exact filename even before the daemon creates it. Existing symlinks, non-sockets and aliased sockets cannot receive restricted grants. Bind permission also permits connecting. It is not a read-only protocol permission.

The JSON-lines backend accepts one UTF-8 `{id, method, params}` request per connection. It enforces bounded frames, connections and timeouts, then returns `{id, ok: true}` after upstream acknowledgment. Host-handled operations, including desktop requests and Herdr reads, may add a projected `result`. Errors include an `id` and `PI_IPC_DENIED`. The backend rejects batches, extra fields, malformed UTF-8 and methods absent from the operation table. It does not forward arbitrary upstream response bodies or implement general JSON-RPC 2.0.

## Trusted endpoint providers

`inherited-socket` captures the absolute Unix socket named by `socketEnvironment` from the original launch environment. It exports a private filtered endpoint under that variable. If the socket was not inherited, project environment loading cannot enable it. Its trusted context contains canonical `cwd`, canonical `home` and numeric `uid`.

`herdr` captures the original workspace-qualified pane, reporting identity and upstream endpoint. Its workspace scope follows that launch identity, not mutable project environment variables. It resolves the selected session directory and retains the session-reference filesystem checks. It requires `HERDR_SOCKET_PATH`. Embedded display metadata uses context bindings unavailable to standalone sessions. A project cannot enable Herdr access by inventing environment hints.

`desktop` runs in the helper process instead of forwarding to an upstream socket. It needs `WAYLAND_DISPLAY` naming an existing socket in `XDG_RUNTIME_DIR`, plus `PI_DESKTOP_WL_COPY`, `PI_DESKTOP_GRIM` and `PI_DESKTOP_PATH`, which the Nix wrapper sets to store paths. Without them the provider exports nothing. It allows `clipboard.copy_text` and `screenshot.capture` for all outputs, one output or a region. There is no clipboard read. The tools receive only `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and the fixed `PATH`. Screenshots return as base64 PNG data, and `pi-desktop` writes them inside the sandbox, so the host never writes to an agent-selected path. Hyprland's `noscreenshare` window rule applies to grim's screencopy capture; the broker adds no separate privacy filter. Ordinary sessions run `pi-desktop` against the compositor directly.

Providers supply trusted facts. Schemas do not prove filesystem ownership, path freshness, editor-buffer ownership or screenshot privacy. A service requiring such checks needs an appropriate host-side guard before its methods can be enabled.

### Read-only Herdr workspace access

The restricted launcher allows `pane.list` and `pane.read` within its launch workspace, across tabs. It also allows the CLI's `ping` handshake, returning only version and protocol metadata. Listing without a workspace always selects the captured workspace. Explicit other-workspace requests fail. The broker checks response pane and workspace identities too, including when a pane has moved.

Use native pane commands:

```sh
herdr pane list
herdr pane read <PANE_ID> --source visible --lines 80
herdr pane read <PANE_ID> --source recent-unwrapped --lines 120
```

Reads return plain text from Herdr's stored terminal snapshots. They never capture history by scrolling or send input to the target. The default limit is 120 lines; requests may select 1–200 lines. Upstream frames are capped at 64 KiB, replies reserve space for their envelope, and lists contain at most 128 panes. Oversized or malformed replies fail closed. Terminal escape sequences and control characters are stripped; Danish letters remain unchanged.

Command execution, agent prompting, pane input, scrolling and other-workspace access remain blocked. Use `pane.read`, not agent history-capture commands. Pane contents may reveal secrets displayed outside the sandbox; that disclosure is explicitly accepted. Treat returned text as untrusted data, not instructions.

## Add a JSON-lines reporting service

The following capability uses the existing `inherited-socket` provider. No service-specific executable handler is needed. The upstream service must speak the request and acknowledgment protocol described above.

```json
{
  "backend": "json-lines",
  "provider": "inherited-socket",
  "socketEnvironment": "TASK_SOCKET",
  "limits": {
    "maxFrameBytes": 16384,
    "maxConnections": 16,
    "clientTimeoutMs": 2000,
    "upstreamTimeoutMs": 1500
  },
  "operations": {
    "task.publish": {
      "schema": {
        "type": "object",
        "properties": {
          "workspace": { "type": "string" },
          "message": {
            "type": "string",
            "format": "ipc-text",
            "maxUtf8Bytes": 1024
          }
        },
        "required": ["workspace", "message"],
        "additionalProperties": false
      },
      "bindings": { "workspace": "cwd" }
    }
  },
  "cleanup": []
}
```

1. Add the declaration under `capabilities.taskReporting` in the manifest.
2. Add `"taskReporting": {}` under `profiles.restricted`.
3. Add tests for permitted requests, rejected requests, captured context and helper shutdown. The configuration-only example in `__tests__/fixtures/ipc-registry.mjs` exercises startup through `ipc-session.mjs`, not just the validator.
4. Rebuild the Nix-owned launcher before using the policy. The service's `TASK_SOCKET` must already exist in the original launch environment.

`schema` uses JSON Schema draft 7 through Ajv. Parameter schemas must be closed objects. `ipc-text` rejects malformed Unicode and C0/C1 controls. `maxUtf8Bytes` limits encoded bytes rather than characters. The validator does not coerce, remove or default caller-supplied values.

A binding maps a parameter name to a trusted context key. A supplied value must match that context exactly. The client cannot submit its own context or ask the broker to select another upstream endpoint.

Cleanup entries select permitted methods and supply constant parameters. The helper fills required bound parameters from trusted context and validates every cleanup message before listening. Optional context bindings must be named explicitly in `optionalBindings`. Cleanup follows acknowledged activity and waits for accepted requests to drain.

## Nono diagnostics in the prompt UI

The managed launcher passes `--log-file` to Nono so tracing warnings do not write over Pi's terminal. Each launch creates an owner-only temporary directory and a `0600` log file. A managed extension watches the file and calls `ctx.ui.notify()`; prompt-ui renders those notifications through its existing notification handling. Print and JSON modes receive sanitized summaries on stderr instead.

The credential-capture wait failure produces `Nono could not wait for the credential capture command.` Other credential-loading failures receive a generic summary. Raw log text and terminal controls never enter the notification. Repeated notification kinds are coalesced for the launch. The watcher reads at most the final 64 KiB and closes on session shutdown.

Both sandboxed and `--no-sandbox` launches use the native log sink. Pi's own stdio and credential-capture policy remain unchanged. The launcher deletes its temporary logs after completion or launch failure. Forced termination can leave private files behind, and the native writer does not rotate or cap the file. This change handles error display; it does not fix the underlying credential-capture failure.

On rvn-pc, the launcher build passed 215 tests and skipped 26, including eight diagnostics tests and a notification reader running inside native Nono confinement. Routing and native Git fsmonitor checks passed. Pi's SDK loader accepted the managed extension. Live interactive prompt-ui rendering and macOS behavior remain unverified; activation and a new Pi session are required.

## Implementation and checks

- `ipc-policy.mjs` validates manifests, selects profiles, resolves endpoint grants, compiles operation schemas and enforces bindings.
- `ipc-session.mjs` starts all selected filters through the supported providers.
- `ipc-bootstrap.mjs`, `json-lines-helper.mjs` and `json-lines-server.mjs` own helper readiness, private endpoints, framing, forwarding and shutdown.
- `herdr-bootstrap.mjs` and `herdr-protocol.mts` retain Herdr-specific context and session-file guards. `herdr-reader.mjs` projects passive workspace snapshots and the CLI handshake; it does not expose terminal control.
- `modules/development/ai/pi/default.nix` builds `packages.<system>.pi-ipc-runtime` and `checks.<system>.pi-ipc`. Tests use the assembled immutable runtime so module resolution matches production.

The scoped source tests run with:

```sh
node --test modules/development/ai/nono/__tests__/{ipc-policy,ipc-bootstrap,ipc-session,json-lines-server,herdr-reporting,herdr-reading}.test.mjs
```

These source tests require the feature-local dependencies. The Nix check supplies the pinned dependencies without a global npm installation. With a Git-backed flake, newly created files must be included in the source before building. Validation during implementation used a filtered working-tree snapshot that included untracked files and excluded runtime sockets and `node_modules`.

The configuration-only fixture verifies automatic helper startup, exact endpoint grants, context binding, sanitized replies and cleanup. Other tests cover invalid manifests, forged project environment, session-reference aliases and teardown after a later helper fails startup.

The native fsmonitor probe in `ipc-workflows.test.mjs` requires `NONO_TEST_BINARY` and `GIT_TEST_BINARY`. Git 2.56.0 on rvn-pc advertises native fsmonitor support. `checks.x86_64-linux.pi-git-fsmonitor` passed the actual-launcher probe, including daemon start/query/stop and IPC-denial checks, with one test and no skips. This focused check remains Linux-only until macOS daemon startup is fixed and verified.

The user waived the native macOS fsmonitor validation gate for default promotion. Git 2.56.0 starts and stops the fixture daemon outside confinement, but `fsmonitor--daemon start` reports `daemon terminated` under nono 0.80.0. The local-only follow-up did not reproduce or verify that failure on a Mac. Promotion does not fix this failure or add broader socket or Mach permissions.

## Validation on rvn-mac

The focused source suite passed 117 tests and skipped 13. It included the pinned generated Herdr reporter and an actual nono launch with Neovim prompt exchange and native-socket denial probes. The separate native Git fsmonitor probe failed as described above. Lightpanda and Linux runtime validation remain outstanding.

Both `pi-ipc-runtime` and `checks.aarch64-darwin.pi-ipc` built from the current working tree. The Nix check validates the generated manifest and runs tests against the assembled runtime. Statix, Deadnix, syntax checks and `git diff --check` passed. The active LSP probe did not confirm any changed file clean because servers were disabled or timed out; the passing evidence is the explicit builds and tests.

On rvn-pc, `checks.x86_64-linux.pi-ipc` passed 72 tests with no skips. The earlier aggregate `nix-unit` attempt timed out while fetching a source from `cache.nixos.org`; it is not recorded as passing.

## Remaining scope

Bounded Hyprland operations, clipboard reads through the desktop broker, image opening, D-Bus credential access and explicit host-container capabilities are not implemented by this registry. Direct Wayland access nevertheless permits clipboard reads and other compositor protocols. Neovim retains its existing dedicated editor transport. Nix daemon, SSH-agent, Wayland, browser and devenv grants remain in their existing code. Those integrations have not been migrated into the catalog.

This registry does not repair Linux's previously identified seccomp address race, io_uring limitations or descriptor passing. An endpoint grant authorizes the peer's full protocol. Passing schema and transport tests does not establish containment of hostile native code. Default promotion does not close the remaining platform and workflow validation gaps.
