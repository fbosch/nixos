---
name: container-service
description: Create NixOS service modules for containerized applications using Podman. Use this skill when the user wants to add a new containerized service (Docker/Podman) to their NixOS configuration in the dendritic flake pattern. Triggers include requests like "add [service] using Docker/Podman", "set up [container] service", or "create a service module for [application]".
---

# Container Service Creator

Create NixOS service modules for running containerized applications with Podman in a dendritic flake layout.

## Overview

This skill guides you through creating a NixOS service module that:
- Runs a containerized application using Podman
- Follows the dendritic pattern (declarative, no path imports)
- Includes proper port management with service-level options
- Provides enable/disable functionality
- Opens firewall ports automatically
- Includes systemd service configuration

## Workflow

### 1. Gather Information

Ask the user for:
- **Service name** (e.g., "termix", "jellyfin")
- **Container image** (e.g., "ghcr.io/lukegus/termix:latest")
- **Default port** (internal container port and desired host port)
- **Volume mounts** (persistent data paths)
- **Environment variables** (if any)
- **Additional configuration** (special networking, dependencies, etc.)

### 2. Create Service Module

Use the template from `assets/service-template.nix` and customize:

1. **Module path**: `modules/services/<service-name>.nix`
2. **Flake module name**: `flake.modules.nixos."services/<service-name>"`
3. **Options**: Define `enable` and `port` options
4. **Systemd service**: Configure container lifecycle
5. **Firewall**: Open necessary ports

Key customization points:
- Container image and tag
- Port mappings (host:container)
- Volume definitions
- Environment variables
- Service dependencies (e.g., `podman.service`)

### 3. Update Host Configuration

1. Add the service module to the host's modules list:
   ```nix
   modules = [
     # ... existing modules
     "services/<service-name>"
     "virtualization/podman"  # Ensure podman is enabled
   ];
   ```

2. Enable the service in `hostImports`:
   ```nix
   hostImports = [
     # ... existing imports
     ({ ... }: {
       services.<service-name>.enable = true;
       # Optionally override port:
       # services.<service-name>.port = 9090;
     })
   ];
   ```

### 4. Verify Podman Module

Ensure the host includes the `virtualization/podman` module. If not present:
- Check if `modules/virtualization/podman.nix` exists
- Add to host's modules list if needed

## Port Management

Services use NixOS module options for ports:

```nix
options.services.<name>.port = lib.mkOption {
  type = lib.types.port;
  default = 8080;  # Set appropriate default
  description = "Port for <service> web interface";
};
```

Benefits:
- Type-safe port validation
- Per-host overridable
- Self-documenting defaults
- No central registry needed

## Port Mapping Pattern

Container services map host ports to container ports:

```nix
-p ${toString config.services.<name>.port}:8080
```

This allows:
- Host-side port customization
- Container runs on its default internal port
- Flexibility for multiple instances or port conflicts

## Template Structure

See `assets/service-template.nix` for a complete, working template that includes:
- Proper NixOS module structure with options and config
- Systemd service configuration
- Podman container lifecycle management
- Volume creation and management
- Firewall configuration
- Service dependencies

## Common Patterns

### Simple Web Service
- Single port exposure
- Data volume for persistence
- Standard container lifecycle

### Service with Multiple Ports
```nix
networking.firewall.allowedTCPPorts = [ 
  config.services.<name>.port 
  config.services.<name>.adminPort
];
```

### Service with Environment Variables
```nix
-e KEY=value \
-e CONFIG_PATH=/data/config \
```

### Service with Host Dependencies
```nix
after = [ "network-online.target" "postgresql.service" ];
requires = [ "postgresql.service" ];
```

## Resources

### assets/
- `service-template.nix` - Complete service module template to copy and customize
