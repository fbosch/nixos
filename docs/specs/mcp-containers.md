# Containerized MCP Server Module — Specification v2

## 1. Problem Statement

Local MCP servers (e.g., `mcp-nixos` via `uvx`, `sequential-thinking` via `bunx`) run with full access to the user's filesystem, network, and environment. A Home Manager module should produce per-server wrapper scripts that run these servers in OCI containers with explicit resource limits, controlled environment variable exposure, and optional network access. The module must work across all hosts in this flake, including rvn-pc (Docker only), rvn-srv (Podman only), and rvn-mac (Podman on Darwin).

## 2. Goals

- G1: Define a Home Manager module at `flake.modules.homeManager."development/mcp-containers"` that declares MCP server containers.
- G2: For each declared server, produce a wrapper script in `~/.local/bin/mcp-container-<name>` that the user references in opencode.json.
- G3: Build OCI images via `pkgs.dockerTools.buildLayeredImage` during Nix evaluation. No registry pulls at runtime.
- G4: Support both `podman` and `docker` runtimes. Auto-detect at invocation time, prefer Podman.
- G5: Use content-addressed image tags derived from the Nix store hash to prevent stale-image reuse.
- G6: Always pass `--init` for PID 1 reaping; enforce memory and PID limits.
- G7: Ship predefined defaults for `mcp-nixos` and `sequential-thinking` that activate on import.
- G8: Serialize image loads with `flock` to avoid concurrent load races.
- G9: Do not generate or modify opencode.json.

## 3. Non-Goals

- NG1: Containerizing remote HTTPS MCP servers (context7, exa).
- NG2: Containerizing `gh mcp` (already sandboxed by the GitHub CLI plugin).
- NG3: Managing or generating opencode.json.
- NG4: Running long-lived containers via Quadlet/systemd.
- NG5: Supporting runtimes other than Podman or Docker.
- NG6: Runtime image pulls from registries.

## 4. Assumptions

1. Hosts importing this module have `podman` or `docker` available on `$PATH`.
2. rvn-pc uses Docker; rvn-srv uses Podman; rvn-mac uses Podman via Home Manager.
3. `pkgs.dockerTools.buildLayeredImage` produces an archive loadable by both `podman load` and `docker load`.
4. MCP servers communicate over stdio and do not require host-exposed ports.
5. opencode.json is dotfiles-managed and updated manually.
6. `flock` is available in `home.packages` (module adds `pkgs.util-linux`).
7. On Darwin, Podman runs via a VM; bind mounts are available with higher latency.
8. Nix store paths are world-readable. Any `env` values in scripts are not secret.

## 5. Glossary

| Term | Definition |
|---|---|
| MCP server | A Model Context Protocol server that communicates over stdio with opencode. |
| Wrapper script | A shell script that loads the OCI image if needed and executes `<runtime> run` with the correct flags. |
| Runtime | `podman` or `docker`, detected at invocation time. |
| Content-addressed tag | Image tag derived from the Nix store hash of the image archive. |
| passEnv | Environment variable names forwarded from the host at runtime. |
| env | Environment variables baked into the wrapper script as literal values. |

## 6. Interfaces and Contracts

### 6.1 Module Registration

```
flake.modules.homeManager."development/mcp-containers"
```

Importing this module enables it (dendritic pattern). No separate enable flag.

### 6.2 Option Interface

All options live under `programs.mcp-containers`.

```nix
programs.mcp-containers = {
  runtime = lib.mkOption {
    type = types.nullOr (types.enum [ "podman" "docker" ]);
    default = null;
    description = ''
      Container runtime to use. When null, the wrapper auto-detects at
      invocation time, preferring podman over docker.
    '';
  };

  servers = lib.mkOption {
    type = types.attrsOf (types.submodule ({ name, ... }: {
      options = {
        image = lib.mkOption {
          type = types.package;
          description = ''
            OCI image archive built with pkgs.dockerTools.buildLayeredImage.
            The image tag is derived from this package's store path hash.
          '';
        };

        command = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Command and arguments to run inside the container.
            When empty, the image's default CMD is used.
          '';
        };

        env = lib.mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = ''
            Environment variables baked into the wrapper script as literal values.
            WARNING: These values are stored in the world-readable /nix/store.
            Do not put secrets here. Use passEnv for runtime values.
          '';
        };

        passEnv = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Environment variable names forwarded from the host at runtime.
            Values are never written to the Nix store.
          '';
        };

        network = lib.mkOption {
          type = types.enum [ "none" "host" "slirp4netns" "bridge" ];
          default = "none";
          description = ''
            Container network mode. On Darwin, "slirp4netns" is remapped to
            "bridge". Default is "none".
          '';
        };

        volumes = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Bind mount specs in "host:container[:options]" format.
            WARNING: Broad mounts (e.g., "/:/host") defeat isolation.
          '';
        };

        memory = lib.mkOption {
          type = types.str;
          default = "512m";
          description = "Memory limit (e.g., '512m', '1g').";
        };

        pidsLimit = lib.mkOption {
          type = types.int;
          default = 256;
          description = "Maximum number of PIDs in the container.";
        };

        extraArgs = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = ''
            Additional arguments passed to the runtime. WARNING: This can
            inject flags like --privileged.
          '';
        };

        readOnly = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Mount the container root filesystem as read-only.";
        };

        tmpfs = lib.mkOption {
          type = types.listOf types.str;
          default = [ "/tmp" ];
          description = "Tmpfs mounts inside the container.";
        };
      };
    }));
    default = { };
    description = "Set of MCP server container definitions.";
  };
};
```

### 6.3 Predefined Server Definitions

Defaults are merged into `programs.mcp-containers.servers` on module import.

#### sequential-thinking

- Image uses `pkgs.bun` and pre-installs `@modelcontextprotocol/server-sequential-thinking` at build time.
- Network: `none`.
- Memory: `512m`.

#### mcp-nixos

- Image uses `pkgs.python3` with `pip install mcp-nixos` at build time.
- Network: `slirp4netns` (remapped to `bridge` on Darwin).
- Memory: `512m`.

These definitions can be overridden or replaced by the user.

### 6.4 Wrapper Script Output

For each server `<name>`, the module produces `~/.local/bin/mcp-container-<name>`.

Wrapper script contract (pseudocode):

```bash
#!/usr/bin/env bash
set -euo pipefail

# Runtime selection
RUNTIME=""
if [[ -n "${MCP_CONTAINER_RUNTIME:-}" ]]; then
  RUNTIME="$MCP_CONTAINER_RUNTIME"
elif command -v podman >/dev/null 2>&1; then
  RUNTIME="podman"
elif command -v docker >/dev/null 2>&1; then
  RUNTIME="docker"
else
  echo "error: neither podman nor docker found on PATH" >&2
  exit 1
fi

MODULE_RUNTIME="<runtime-option-or-empty>"
if [[ -n "$MODULE_RUNTIME" ]]; then
  RUNTIME="$MODULE_RUNTIME"
fi

IMAGE_ARCHIVE="<nix-store-path-to-image.tar.gz>"
IMAGE_TAG="<name>:nix-<store-hash>"
LOCK_FILE="/tmp/mcp-container-<name>.lock"

(
  ${pkgs.util-linux}/bin/flock -x 200
  if ! "$RUNTIME" image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    if ! "$RUNTIME" load -i "$IMAGE_ARCHIVE"; then
      "$RUNTIME" rmi "$IMAGE_TAG" >/dev/null 2>&1 || true
      echo "error: failed to load image $IMAGE_TAG" >&2
      exit 1
    fi
  fi
) 200>"$LOCK_FILE"

exec "$RUNTIME" run \
  --rm \
  --init \
  --interactive \
  --network=<network> \
  --memory=<memory> \
  --pids-limit=<pidsLimit> \
  <--read-only if readOnly> \
  <--tmpfs entries> \
  <--env KEY=VALUE for env> \
  <--env KEY for passEnv> \
  <--volume entries> \
  <extraArgs> \
  "$IMAGE_TAG" \
  <command args if non-empty>
```

### 6.5 Content-Addressed Image Tags

Tags are derived from the image archive store hash:

```nix
let
  hash = builtins.substring 11 32 (baseNameOf image.outPath);
  tag = "${name}:nix-${hash}";
in
  pkgs.dockerTools.buildLayeredImage { inherit tag; ... }
```

### 6.6 OpenCode Integration

User manually references wrapper scripts in opencode.json:

```json
{
  "mcp": {
    "nixos": {
      "type": "local",
      "command": ["mcp-container-mcp-nixos"]
    },
    "sequential-thinking": {
      "type": "local",
      "command": ["mcp-container-sequential-thinking"]
    }
  }
}
```

## 7. Invariants

| ID | Invariant | Enforcement |
|---|---|---|
| INV-1 | Wrapper references exactly one image archive path. | Nix evaluation. |
| INV-2 | Image archive path is a direct wrapper dependency (prevents GC). | Nix evaluation. |
| INV-3 | `--rm` is always passed. | Wrapper template. |
| INV-4 | `--interactive` is always passed. | Wrapper template. |
| INV-5 | `--tty` is never passed. | Wrapper template. |
| INV-6 | `--memory` and `--pids-limit` are always passed. | Wrapper template. |
| INV-7 | Default network is `none`. | Option default. |
| INV-8 | `--init` is always passed. | Wrapper template. |
| INV-9 | Image tag is content-addressed from the store hash. | Nix evaluation. |
| INV-10 | Image load is serialized with `flock`. | Wrapper template. |
| INV-11 | `env` values are non-secret and stored in Nix store. | Documentation warning. |
| INV-12 | On Darwin, `slirp4netns` is remapped to `bridge`. | Nix evaluation. |

## 8. Behavior

### 8.1 Happy Path

1. User imports `development/mcp-containers` in HM.
2. Nix builds images and installs wrapper scripts in `~/.local/bin/`.
3. User updates opencode.json to reference wrapper scripts.
4. Wrapper selects runtime, loads image if missing, execs container.
5. MCP protocol flows over stdio; container exits on shutdown.

### 8.2 Edge Cases

- EC-1: No runtime on PATH → wrapper exits 1 with error.
- EC-2: Flake update changes image hash → new tag triggers load; old image pruned by autoPrune.
- EC-3: Concurrent starts → `flock` serializes load.
- EC-4: Interrupted load → `rmi` cleanup; next run retries.
- EC-5: Nix GC removes image archive → wrapper would be GCed too; if invoked from old generation, load fails with missing archive.
- EC-6: Docker-only host (rvn-pc) → wrapper uses Docker; `image inspect` path works.
- EC-7: `slirp4netns` on Darwin → remapped to `bridge`.
- EC-8: Container exits non-zero → exit code propagates to opencode.
- EC-9: passEnv var unset on host → empty env var inside container.
- EC-10: readOnly blocks writes → user adds tmpfs or volumes if needed.
- EC-11: Over-broad volumes defeat isolation → documented warning.
- EC-12: `extraArgs` can override security defaults → documented warning.

### 8.3 Error Handling

| Error | Detection | Response | Exit Code |
|---|---|---|---|
| No runtime | `command -v` fails | stderr + exit | 1 |
| Load fails | non-zero load exit | attempt `rmi`, stderr | 1 |
| Missing archive | load fails with missing file | stderr + exit | 1 |
| Runtime run error | non-zero runtime exit | propagated | runtime exit |

## 9. State Model

### 9.1 Image Lifecycle

```
[Nix build] -> [Image archive in store]
      | first run
      v
[Runtime image loaded with nix-<hash> tag]
      | flake update
      v
[New tag loaded] (old tag pruned by runtime autoPrune)
```

### 9.2 Wrapper Invocation Lifecycle

```
Detect runtime -> Acquire lock -> Inspect image -> Load if missing -> Exec run -> Exit
```

## 10. Performance and Constraints

| Constraint | Value | Note |
|---|---|---|
| Default memory | 512 MB | Avoids Node.js OOM for typical workloads. |
| Default PIDs | 256 | Enough for runtime helpers. |
| First run load | 1–5 seconds | Local load from Nix store. |
| Subsequent runs | ~0 ms | Image inspect short-circuit. |
| Darwin latency | Higher | Podman VM filesystem sharing. |

## 11. Observability

- Wrapper exits with runtime exit code.
- Errors are written to stderr.
- `MCP_CONTAINER_DEBUG=1` prints runtime selection and load status to stderr.
- Images can be listed via `<runtime> images | grep nix-`.

## 12. Security and Safety

- `env` values are stored in `/nix/store`. Do not place secrets there.
- `passEnv` passes host values at runtime only.
- `volumes` can bypass filesystem isolation; keep mounts minimal and prefer `:ro`.
- `extraArgs` can disable security hardening; use only when needed.
- Default `network = none` blocks outbound access unless explicitly set.

## 13. Test Plan

### 13.1 Nix Evaluation Tests

- T-E1: Module evaluates with defaults.
- T-E2: Custom server with all options evaluates.
- T-E3: Darwin remaps `slirp4netns` to `bridge`.
- T-E4: Linux keeps `slirp4netns`.
- T-E5: Tag includes store hash substring.
- T-E6: Changing image contents changes tag.
- T-E7: `runtime = "docker"` is baked into wrapper.
- T-E8: `runtime = null` includes auto-detection.
- T-E9: Empty `command` omits CMD args.
- T-E10: `readOnly = false` omits `--read-only`.

### 13.2 Wrapper Script Content Tests

- T-W1: Contains `--init`.
- T-W2: Contains `--rm`.
- T-W3: Contains `--interactive`.
- T-W4: Does not contain `--tty` or `-t`.
- T-W5: Contains `--memory=512m`.
- T-W6: Contains `--pids-limit=256`.
- T-W7: Contains `flock` (util-linux path).
- T-W8: Contains image archive store path.
- T-W9: Contains `--env KEY=VALUE` for each `env` entry.
- T-W10: Contains `--env KEY` for each `passEnv` entry.
- T-W11: Contains `--read-only` when enabled.
- T-W12: Contains `--volume` entries for each `volumes` entry.
- T-W13: Contains `--network=none` for default.
- T-W14: Contains `rmi` cleanup on load failure.
- T-W15: Uses `image inspect` (Docker-compatible).
- T-W16: Contains `--tmpfs` entries for each `tmpfs` entry.

### 13.3 Integration Tests

- T-I1: Podman path works (load + run).
- T-I2: Docker path works (load + run).
- T-I3: Second invocation skips load.
- T-I4: Concurrent load serializes.
- T-I5: New image hash loads after flake update.
- T-I6: `mcp-container-mcp-nixos` can reach NixOS API.
- T-I7: `mcp-container-sequential-thinking` responds to MCP initialize.
- T-I8: Memory limit triggers OOM on large allocation.
- T-I9: `network = none` blocks outbound access.
- T-I10: `MCP_CONTAINER_RUNTIME=docker` forces Docker on Podman hosts.
- T-I11: Darwin Podman path works.
- T-I12: Interrupted load recovers on retry.

## 14. Open Questions

None.
