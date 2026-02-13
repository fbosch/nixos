# Module Creation Patterns

This document provides detailed patterns for creating different types of modules in the dendritic flake structure.

## Module Categories

Modules are organized by category based on their purpose:

### System Categories (NixOS/Darwin)
- **services/** - System services (daemons, servers)
- **virtualization/** - Container and VM support
- **hardware/** - Hardware-specific configuration
- **system/** - Core system settings
- **security/** - Security and authentication
- **presets/** - Feature collections

### User Categories (Home Manager)
- **applications/** - User applications
- **desktop/** - Desktop environment components
- **development/** - Development tools and environments
- **shell/** - Shell configuration
- **fonts/** - Font configuration

### Mixed Categories (Can contain both NixOS and Home Manager)
- **hosts/** - Host-specific configurations
- **users/** - User account definitions

### Special Categories
- **flake-parts/** - Flake infrastructure modules
- **secrets/** - Encrypted secrets (SOPS)

## Pattern 1: Simple NixOS Service

**Use when**: Adding a system service that runs as a daemon

**Example**: nginx, postgresql, atticd

**Structure**:
```nix
_:
{
  flake.modules.nixos."services/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.<name>;
    in
    {
      options.services.<name> = {
        # Options for customization (optional)
        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for <name> service";
        };
      };

      config = {
        # Enable service by default
        services.<name> = {
          enable = true;
          port = cfg.port;
          # Other service config
        };

        # Open firewall if needed
        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
```

**Key Points**:
- Service enables automatically when module is imported
- Use options only for host-specific customization
- Include firewall rules if service needs network access
- Use `lib.mkDefault` for values that hosts might override

## Pattern 2: Home Manager Program

**Use when**: Adding a user-level application or program

**Example**: firefox, git, neovim

**Structure**:
```nix
_:
{
  flake.modules.homeManager."programs/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      # No options needed unless customization required
      config = {
        programs.<name> = {
          enable = true;
          # Program-specific config
        };

        # Additional user packages if needed
        home.packages = with pkgs; [
          # Related packages
        ];
      };
    };
}
```

**Key Points**:
- Program enables by default
- Configuration is user-specific
- Can include dotfiles, themes, plugins
- Use `lib.mkDefault` for user-overridable settings

## Pattern 3: System Configuration

**Use when**: Configuring system-level settings that aren't services

**Example**: locale, console, networking

**Structure**:
```nix
_:
{
  flake.modules.nixos."system/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # System configuration
        systemd.extraConfig = "...";
        
        boot.kernel.sysctl = {
          "vm.swappiness" = lib.mkDefault 60;
        };
        
        # Environment packages
        environment.systemPackages = with pkgs; [
          # System tools
        ];
      };
    };
}
```

**Key Points**:
- No options unless host-specific customization needed
- Use `lib.mkDefault` for tunable values
- Focus on system-wide settings

## Pattern 4: Multi-Context Module

**Use when**: Feature spans both system and user configuration

**Example**: GNOME (system packages + user settings)

**Structure**:
```nix
{ config, ... }:
{
  # NixOS system-level module
  flake.modules.nixos."desktop/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # System-level config
        services.xserver.enable = true;
        environment.systemPackages = with pkgs; [
          # Desktop packages
        ];
        
        # Include Home Manager auxiliary module
        home-manager.sharedModules = [
          config.flake.modules.homeManager."desktop/<name>"
        ];
      };
    };

  # Home Manager user-level module
  flake.modules.homeManager."desktop/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # User-level config
        dconf.settings = {
          # User preferences
        };
      };
    };
}
```

**Key Points**:
- Both modules in same file
- NixOS module includes Home Manager module via `sharedModules`
- System config separate from user config
- Auxiliary module is private (only imported by parent)

## Pattern 5: Containerized Service

**Use when**: Running a service in Docker/Podman container

**Example**: termix, redlib

**Structure**:
```nix
_:
{
  flake.modules.nixos."services/containers/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.<name>-container;
    in
    {
      options.services.<name>-container = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable <name> container service";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 8080;
          description = "Port for <name> web interface";
        };
      };

      config = lib.mkIf cfg.enable {
        systemd.services.<name>-container = {
          description = "<Name> Container Service";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" "podman.service" ];
          requires = [ "podman.service" ];

          serviceConfig = {
            Type = "simple";
            Restart = "always";
          };

          script = ''
            ${pkgs.podman}/bin/podman volume create <name>-data || true
            ${pkgs.podman}/bin/podman rm -f <name> || true
            
            ${pkgs.podman}/bin/podman run \
              --name <name> \
              --rm \
              -p ${toString cfg.port}:8080 \
              -v <name>-data:/data \
              <image>:<tag>
          '';
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];
      };
    };
}
```

**Key Points**:
- Requires podman/docker module as dependency
- Use systemd service for lifecycle management
- Include volume management
- Use `lib.mkIf cfg.enable` pattern for containerized services (common convention)

## Pattern 6: Collector Module

**Use when**: Multiple sources contribute to same configuration

**Example**: Syncthing device IDs across hosts

**Structure**:

```nix
# In modules/services/syncthing.nix
_:
{
  flake.modules.nixos.syncthing = {
    services.syncthing.enable = true;
    services.syncthing.dataDir = lib.mkDefault "/var/lib/syncthing";
  };
}

# In modules/hosts/host1.nix
_:
{
  flake.modules.nixos.syncthing = {
    services.syncthing.settings.devices.host1 = {
      id = "ABC-123-DEF";
    };
  };
}

# In modules/hosts/host2.nix
_:
{
  flake.modules.nixos.syncthing = {
    services.syncthing.settings.devices.host2 = {
      id = "XYZ-789-GHI";
    };
  };
}
```

**Key Points**:
- Same aspect name across multiple files
- Configs merge automatically
- Base service in dedicated file
- Host-specific config in host modules
- All definitions merge when both hosts import syncthing

## Pattern 7: Generic Module

**Use when**: Shared across NixOS and Darwin, or platform-agnostic

**Example**: Constants, shared functions

**Structure**:
```nix
_:
{
  flake.modules.generic."<name>" =
    { config
    , lib
    , ...
    }:
    {
      options.<name> = {
        # Platform-agnostic options
      };

      config = {
        # Platform-agnostic config
      };
    };
}
```

**Key Points**:
- No platform-specific configuration
- Importable into nixos, darwin, or homeManager modules
- Use for shared constants, utilities, functions

## Pattern 8: Preset Module

**Use when**: Grouping related features together

**Example**: "server" preset, "desktop" preset

**Structure**:
```nix
{ config, ... }:
{
  flake.modules.nixos."presets/<name>" =
    { ... }:
    {
      imports = config.flake.lib.resolve [
        "users"
        "security"
        "development/tools"
        "shell/fish"
        "system/core"
        "vpn"
      ];
    };
}
```

**Key Points**:
- Only imports, no direct config
- Uses `config.flake.lib.resolve` helper
- Groups coherent feature sets
- Simplifies host configuration

## Pattern 9: Module with Secrets

**Use when**: Module needs encrypted credentials

**Example**: Attic client with admin token

**Structure**:
```nix
_:
{
  flake.modules.nixos."services/<name>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.<name>;
      tokenFile = config.sops.secrets.<name>-token.path;
    in
    {
      options.services.<name> = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };

      config = lib.mkIf cfg.enable {
        # Define secret
        sops.secrets.<name>-token = {
          mode = "0400";
          owner = "root";
        };

        # Use secret in service
        systemd.services.<name> = {
          script = ''
            TOKEN=$(cat ${tokenFile})
            # Use $TOKEN
          '';
        };
      };
    };
}
```

**Key Points**:
- Define secret in `sops.secrets.<name>`
- Reference via `config.sops.secrets.<name>.path`
- Set appropriate permissions and owner
- Secret must exist in the expected file under `secrets/*.yaml`

## Naming Conventions

### Module Names
- Use lowercase with hyphens: `my-service`
- Match upstream package/service name when possible
- Be specific: `attic-client` not just `attic`

### Aspect Paths
- Use category prefix: `services/nginx`, `programs/git`
- Match file path structure
- Keep consistent with existing modules

### Option Names
- Follow NixOS conventions: `services.<name>`, `programs.<name>`
- Use descriptive names: `port`, `dataDir`, `user`
- Group related options: `services.<name>.nginx.port`

## Import Resolution

Use the `config.flake.lib.resolve` helper for imports:

```nix
imports = config.flake.lib.resolve [
  "services/nginx"
  "virtualization/podman"
];

# For Home Manager context
home-manager.users.<user>.imports = config.flake.lib.resolveHm [
  "programs/git"
  "shell/fish"
];
```

This resolves string paths to actual module references.

## Validation

After creating a module:

1. Check it follows dendritic pattern (use dendritic-pattern skill)
2. Verify no conditional imports
3. Ensure proper module class
4. Test import in a host configuration
5. Verify options work as expected
6. Check for merge conflicts with existing modules
