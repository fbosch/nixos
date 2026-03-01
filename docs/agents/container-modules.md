# Container Module Authoring

All containers run as Podman Quadlet units (systemd `.container` files). This document defines the conventions for new container modules.

## Image Sources

**Pre-built registry images are always preferred.** Reference them directly in the Quadlet file with an `imageTag` option pinned to a specific version (never `latest`).

If the upstream does not publish images (source-only project), ship a **build helper command** — not a systemd service:
- Use `pkgs.writeShellScriptBin "build-<name>-images"` for the script
- Expose it via `environment.systemPackages`
- Reference locally built images with `Image=localhost/<name>:latest` and `Pull=never`
- See `modules/services/containers/openmemory.nix` for the full pattern

**Never use a custom systemd service to build images.** This creates ordering problems, makes rebuilds hard to reason about, and violates the Quadlet model.

## Module Structure

### Outer function signature

Use `_: {` when the module needs no flake-level config:

```nix
_: {
  flake.modules.nixos."services/containers/myapp" = { config, lib, ... }:
    let cfg = config.services.myapp-container; in { ... };
}
```

Use `{ config, ... }: let ... in {` only when accessing `config.flake.lib.*` at the outer scope (e.g. to destructure `sopsHelpers`):

```nix
{ config, ... }:
let inherit (config.flake.lib) sopsHelpers; in
{
  flake.modules.nixos."services/containers/myapp" = { config, lib, ... }: ...;
}
```

### Options namespace

Use `options.services.<name>-container` for custom container services. Always bind `cfg = config.services.<name>-container` at the top of the inner `let` block.

### No enable flag

Importing the module enables the service. Do **not** add a top-level `enable` option.

If the service requires credentials to function, guard with an `assertion` instead:

```nix
assertions = [{
  assertion = cfg.envFile != null;
  message = "myapp-container: envFile must be set (SOPS template path)";
}];
```

### Firewall rules and port registration

Each container module is responsible for both declaring its ports in `services.containerPorts` **and** opening them in `networking.firewall`. The `validation/container-port-conflicts` module only checks for port conflicts — it does not generate firewall rules.

```nix
# ✅ correct: both declarations live in the module
services.containerPorts = lib.mkAfter [{
  service = "myapp-container";
  tcpPorts = [ cfg.port ];
}];

networking.firewall.allowedTCPPorts = [ cfg.port ];
```

`services.containerPorts` is still required — omitting it means the conflict validator can't catch collisions with other services.

## Quadlet File

Write the container unit to `environment.etc."containers/systemd/<name>.container"`:

```nix
environment.etc."containers/systemd/myapp.container".text = ''
  [Unit]
  Description=MyApp - short description
  After=network-online.target
  Wants=network-online.target

  [Container]
  ContainerName=myapp
  Image=docker.io/vendor/myapp:${cfg.imageTag}
  PublishPort=${toString cfg.port}:8080
  Volume=${cfg.dataDir}:/data
  EnvironmentFile=${config.sops.templates."myapp-env".path}
  Memory=512m
  PidsLimit=500
  Ulimit=nofile=2048:4096
  LogDriver=journald
  LogOpt=tag=myapp

  [Service]
  Restart=always
  RestartSec=10
  CPUQuota=100%
  TimeoutStartSec=120

  [Install]
  WantedBy=multi-user.target
'';
```

### Resource limits — native Quadlet fields

Use native Quadlet/systemd fields. Only use `PodmanArgs=` for things with no native equivalent.

| Limit | Native field | Location |
|---|---|---|
| Memory hard limit | `Memory=512m` | `[Container]` |
| Process/thread cap | `PidsLimit=500` | `[Container]` |
| File descriptor limits | `Ulimit=nofile=2048:4096` | `[Container]` |
| Shared memory | `ShmSize=64m` | `[Container]` |
| CPU quota | `CPUQuota=100%` | `[Service]` |
| Memory soft limit | `PodmanArgs=--memory-reservation=X` | `[Container]` (no native) |
| CPU count (--cpus) | `PodmanArgs=--cpus=X` | `[Container]` (no native) |

`CPUQuota=100%` ≈ 1 core; `CPUQuota=200%` ≈ 2 cores.

Do **not** use `PodmanArgs=--memory=` or `PodmanArgs=--pids-limit=` — use the native fields above.

### Renovate compatibility

Use option names that end in `imageTag` or `ImageTag` so Renovate can detect updates for interpolated image references. Examples: `imageTag`, `redisImageTag`, `core.imageTag`.

### Health checks

Add health checks for services with a stable health endpoint:

```
HealthCmd=wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1
HealthInterval=30s
HealthTimeout=10s
HealthStartPeriod=30s
HealthRetries=3
```

## Volumes

**Named Podman volumes** (`.volume` files) — for data that is opaque, managed by the container, and not user-edited:

```nix
environment.etc."containers/systemd/myapp-data.volume".text = ''
  [Volume]
  VolumeName=myapp-data
'';
```

Reference in container: `Volume=myapp-data.volume:/data`

**Host directories** — for user-owned data, config files, or data that may be backed up/edited directly. Create with `systemd.tmpfiles.rules`:

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0755 root root -"
];
```

Reference in container: `Volume=${cfg.dataDir}:/data`

## SOPS / Secrets

Wire secrets through `sops.secrets` + `sops.templates`. Use `sopsHelpers` from `config.flake.lib`:

```nix
{ config, ... }:
let inherit (config.flake.lib) sopsHelpers; in
{
  flake.modules.nixos."services/containers/myapp" = { config, lib, ... }:
    let
      cfg = config.services.myapp-container;
      containersFile = ../../../secrets/containers.yaml;
    in {
      config = {
        sops = {
          secrets = sopsHelpers.mkSecretsWithOpts containersFile sopsHelpers.rootOnly [
            "myapp-api-key"
            "myapp-secret"
          ];

          templates."myapp-env" = {
            content = ''
              MYAPP_API_KEY=${config.sops.placeholder.myapp-api-key}
              MYAPP_SECRET=${config.sops.placeholder.myapp-secret}
            '';
            mode = "0400";
          };
        };

        # Auto-wire the rendered template path as the default envFile
        services.myapp-container.envFile = lib.mkDefault (
          lib.attrByPath [ "sops" "templates" "myapp-env" "path" ] null config
        );
      };
    };
}
```

## Multi-Container Setups

When multiple containers need to communicate, use a Podman network file:

```nix
environment.etc."containers/systemd/myapp.network".text = ''
  [Network]
  NetworkName=myapp
'';
```

Always include `NetworkName=`. Reference it in containers with `Network=myapp.network`.

Declare service ordering with `After=` and `Requires=` in `[Unit]`:

```
After=network-online.target myapp-db.service
Wants=network-online.target
Requires=myapp-db.service
```

## Checklist for New Modules

- [ ] Registry image with an `imageTag` option pinned to a specific version (never `"latest"`)
- [ ] No `enable` option — use assertions for credential requirements
- [ ] `cfg = config.services.<name>-container` alias in `let`
- [ ] Quadlet file under `environment.etc."containers/systemd/<name>.container"`
- [ ] `services.containerPorts` declaration — no direct `networking.firewall.*`
- [ ] Resource limits use native Quadlet fields
- [ ] `LogDriver=journald` + `LogOpt=tag=<name>` on every container
- [ ] `[Service]` has `Restart=always`, `RestartSec=10`, `TimeoutStartSec=`
- [ ] `[Install]` has `WantedBy=multi-user.target`
- [ ] Secrets wired via `sops.templates`, not inline in container env
- [ ] Named volumes have a `.volume` file with `VolumeName=`
- [ ] Multi-container networks have a `.network` file with `NetworkName=`
- [ ] Port added to `docs/agents/service-ports.md`
