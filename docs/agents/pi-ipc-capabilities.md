# Pi IPC capabilities

The IPC registry configures selected-repository fsmonitor access and bounded JSON-lines filters. The restricted launcher remains opt-in. Git fsmonitor's native macOS probe currently fails inside nono, so this implementation does not unblock default rollout.

## Configuration and ownership

The default manifest is `modules/development/ai/nono/scripts/ipc-capabilities.json`. The flake-parts option `piIpcRegistry` can supply a complete replacement manifest. Nix serializes the selected configuration into the store and builds a runtime with Ajv 8.20.0 and its locked dependencies.

The binary wrapper forces `PI_IPC_MANIFEST` to the store path. The launcher loads and validates that file before loading the project environment. Project environment changes cannot replace the captured registry, choose upstream sockets, or forge Herdr identity.

The manifest has a capability catalog and profile selections. A capability declaration alone does not enable it. The `ordinary` profile preserves the existing direct fsmonitor behavior on macOS. The `restricted` profile selects the bounded Herdr filter, the desktop broker and exact fsmonitor bind/connect grants on macOS and Linux.

The Linux candidate also grants the exact inherited Wayland socket outside the registry. This is full compositor protocol access, including clipboard reads and any exposed screen-capture or input-injection protocols. It is not constrained by the desktop broker's operation schemas. The launcher captures the socket before project environment loading and exports its absolute path. It does not grant the runtime directory or force OSC 52. D-Bus, Hyprland control and other unselected sockets remain denied.

The candidate still excludes `/dev/shm`, so direct `grim` may fail when allocating image buffers. Use `pi-desktop screenshot` for the broker path.

Malformed manifests, unknown capabilities or providers, invalid schemas, conflicting socket exports and missing required launch bindings fail startup. There is no direct-service fallback after filter failure. The ordinary Linux nono profile still uses unrestricted Unix IPC mediation; selecting a filter there would not establish socket confinement.

## Supported mechanisms

| Backend | Declaration | Authority |
| --- | --- | --- |
| `endpoint` | `discovery = selected-git-metadata`, a socket filename, and a profile-specific access mode | Full protocol access to each selected endpoint |
| `json-lines` | A trusted endpoint provider, exported socket variable, operation schemas, context bindings, limits and cleanup messages | Only accepted messages; forwarding providers reply with acknowledgments, host-handled providers may return a result |

The endpoint backend resolves selected worktree, shared Git and explicitly referenced Git metadata directories. `connect-existing` grants existing user-owned, unaliased sockets. `bind` grants the exact filename even before the daemon creates it. Existing symlinks, non-sockets and aliased sockets cannot receive restricted grants. Bind permission also permits connecting. It is not a read-only protocol permission.

The JSON-lines backend accepts one UTF-8 `{id, method, params}` request per connection. It enforces bounded frames, connections and timeouts, then returns only `{id, ok: true}` after upstream acknowledgment. Providers handled in the helper process, such as `desktop`, may add a `result` field. It rejects batches, extra fields, malformed UTF-8 and methods absent from the operation table. It does not forward upstream response bodies or implement general JSON-RPC 2.0.

## Trusted endpoint providers

`inherited-socket` captures the absolute Unix socket named by `socketEnvironment` from the original launch environment. It exports a private filtered endpoint under that variable. If the socket was not inherited, project environment loading cannot enable it. Its trusted context contains canonical `cwd`, canonical `home` and numeric `uid`.

`herdr` captures the original pane, reporting identity and upstream endpoint. It also resolves the selected session directory and retains the session-reference filesystem checks. It requires `HERDR_SOCKET_PATH`. Embedded display metadata uses context bindings that are unavailable to standalone sessions. A project cannot enable Herdr reporting by inventing environment hints.

`desktop` runs in the helper process instead of forwarding to an upstream socket. It needs `WAYLAND_DISPLAY` naming an existing socket in `XDG_RUNTIME_DIR`, plus `PI_DESKTOP_WL_COPY`, `PI_DESKTOP_GRIM` and `PI_DESKTOP_PATH`, which the Nix wrapper sets to store paths. Without them the provider exports nothing. It allows `clipboard.copy_text` and `screenshot.capture` for all outputs, one output or a region. There is no clipboard read. The tools receive only `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` and the fixed `PATH`. Screenshots return as base64 PNG data, and `pi-desktop` writes them inside the sandbox, so the host never writes to an agent-selected path. Hyprland's `noscreenshare` window rule applies to grim's screencopy capture; the broker adds no separate privacy filter. Ordinary sessions run `pi-desktop` against the compositor directly.

Providers supply trusted facts. Schemas do not prove filesystem ownership, path freshness, editor-buffer ownership or screenshot privacy. A service requiring such checks needs an appropriate host-side guard before its methods can be enabled.

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

## Implementation and checks

- `ipc-policy.mjs` validates manifests, selects profiles, resolves endpoint grants, compiles operation schemas and enforces bindings.
- `ipc-session.mjs` starts all selected filters through the supported providers.
- `ipc-bootstrap.mjs`, `json-lines-helper.mjs` and `json-lines-server.mjs` own helper readiness, private endpoints, framing, forwarding and shutdown.
- `herdr-bootstrap.mjs` and `herdr-protocol.mts` retain Herdr-specific context and session-file guards. They no longer own the transport implementation.
- `modules/development/ai/pi/default.nix` builds `packages.<system>.pi-ipc-runtime` and `checks.<system>.pi-ipc`. Tests use the assembled immutable runtime so module resolution matches production.

The scoped source tests run with:

```sh
node --test modules/development/ai/nono/__tests__/{ipc-policy,ipc-bootstrap,ipc-session,json-lines-server,herdr-reporting}.test.mjs
```

These source tests require the feature-local dependencies. The Nix check supplies the pinned dependencies without a global npm installation. With a Git-backed flake, newly created files must be included in the source before building. Validation during implementation used a filtered working-tree snapshot that included untracked files and excluded runtime sockets and `node_modules`.

The configuration-only fixture verifies automatic helper startup, exact endpoint grants, context binding, sanitized replies and cleanup. Other tests cover invalid manifests, forged project environment, session-reference aliases and teardown after a later helper fails startup.

The native fsmonitor probe in `ipc-workflows.test.mjs` additionally requires `NONO_TEST_BINARY` and `GIT_TEST_BINARY` on macOS. It remains a rollout gate. Git 2.56.0 starts and stops the fixture daemon outside confinement, but `fsmonitor--daemon start` reports `daemon terminated` under nono 0.80.0. No broader socket or Mach permissions were added to hide this failure.

## Validation on rvn-mac

The focused source suite passed 117 tests and skipped 13. It included the pinned generated Herdr reporter and an actual nono launch with Neovim prompt exchange and native-socket denial probes. The separate native Git fsmonitor probe failed as described above. Lightpanda and Linux runtime validation remain outstanding.

Both `pi-ipc-runtime` and `checks.aarch64-darwin.pi-ipc` built from the current working tree. The Nix check validates the generated manifest and runs tests against the assembled runtime. Statix, Deadnix, syntax checks and `git diff --check` passed. The active LSP probe did not confirm any changed file clean because servers were disabled or timed out; the passing evidence is the explicit builds and tests.

The `x86_64-linux` IPC check evaluates, but was not built or run. The aggregate `nix-unit` attempt timed out while fetching a source from `cache.nixos.org`; it is not recorded as passing.

## Remaining scope

Bounded Hyprland operations, clipboard reads through the desktop broker, image opening, D-Bus credential access and explicit host-container capabilities are not implemented by this registry. Direct Wayland access nevertheless permits clipboard reads and other compositor protocols. Neovim retains its existing dedicated editor transport. Nix daemon, SSH-agent, Wayland, browser and devenv grants remain in their existing code. Those integrations have not been migrated into the catalog.

This registry does not repair Linux's previously identified seccomp address race, io_uring limitations or descriptor passing. An endpoint grant authorizes the peer's full protocol. Passing schema and transport tests does not establish containment of hostile native code. Linux runtime validation and the broader default-rollout gates remain outstanding.
