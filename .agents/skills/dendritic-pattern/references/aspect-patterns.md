# Dendritic Aspect Patterns

This document catalogs the 8 standard aspect patterns used in dendritic flakes.

## Critical Pattern Rules

Before diving into specific patterns, understand these fundamental rules:

### 1. Import to Enable Pattern

Features **activate when imported**, not via enable options:

```nix
# ✅ DENDRITIC WAY
flake.modules.nixos.nginx = {
  services.nginx.enable = true;  # Enabled by default
  services.nginx.port = lib.mkDefault 80;  # User can override
};

# Usage - just import
flake.modules.nixos.myHost = {
  imports = [ inputs.self.modules.nixos.nginx ];  # Activated!
};
```

### 2. lib.mkMerge for Merging

**ALWAYS use `lib.mkMerge`** instead of `//`:

```nix
# ✅ CORRECT
config = lib.mkMerge [
  baseConfig
  additionalConfig
  (lib.mkIf condition { ... })
];

# ❌ WRONG - shallow merge loses data
config = baseConfig // additionalConfig;
```

### 3. Collector Aspect: Same Name Merging

**Multiple files can define the same aspect** - configs merge automatically:

```nix
# In syncthing.nix
flake.modules.nixos.syncthing = {
  services.syncthing.enable = true;
};

# In host1.nix - SAME NAME
flake.modules.nixos.syncthing = {
  services.syncthing.settings.devices.host1.id = "ABC-123";
};

# In host2.nix - SAME NAME
flake.modules.nixos.syncthing = {
  services.syncthing.settings.devices.host2.id = "XYZ-789";
};

# Result: All merge together automatically!
```

See [validation-rules.md](validation-rules.md) for complete rules.

## Pattern Overview

| Aspect | Plural | Purpose | Examples |
|--------|--------|---------|----------|
| host | hosts | Physical/virtual machines | desktop, server, laptop |
| service | services | System services (NixOS) | nginx, postgresql, plex |
| program | programs | User programs (Home Manager) | firefox, vscode, git |
| module | modules | Feature collections | desktop-env, dev-tools |
| class | classes | Aspect definitions | host.nix, service.nix |
| container | containers | Containerized apps | jellyfin-docker, traefik |
| vm | vms | Virtual machines | dev-vm, test-env |
| secret | secrets | Encrypted credentials | api-keys, passwords |

## 1. Host Aspect

**Purpose:** Define physical or virtual machines

**File Location:** `modules/hosts/<hostname>.nix`

**Structure:**
```nix
{ config, lib, ... }:
let
  cfg = config.flake.modules.host.<hostname>;
in {
  options.flake.modules.host.<hostname> = {
    enable = lib.mkEnableOption "<hostname>";
    # Host-specific options
  };

  config = lib.mkIf cfg.enable {
    flake.nixosConfigurations.<hostname> = {
      system = "x86_64-linux";
      modules = [
        ./../../machines/<hostname>/configuration.nix
      ];
    };
    
    # Enable features this host uses
    flake.modules.service.nginx.enable = true;
    flake.modules.program.firefox.enable = true;
  };
}
```

**Key Points:**
- Hosts compose features, don't define them
- One file per physical/virtual machine
- References machine-specific configs in `machines/` directory

## 2. Service Aspect

**Purpose:** System-level services (NixOS modules)

**File Location:** `modules/services/<service-name>.nix`

**Structure:**
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.flake.modules.service.<service-name>;
in {
  options.flake.modules.service.<service-name> = {
    enable = lib.mkEnableOption "<service-name>";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Service port";
    };
  };

  config = lib.mkIf cfg.enable {
    services.<service-name> = {
      enable = true;
      port = cfg.port;
    };
    
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
```

**Key Points:**
- Maps to NixOS `services.*` options
- Includes firewall, systemd, and related system config
- May include nginx reverse proxy config

## 3. Program Aspect

**Purpose:** User-level applications (Home Manager modules)

**File Location:** `modules/programs/<program-name>.nix`

**Structure:**
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.flake.modules.program.<program-name>;
in {
  options.flake.modules.program.<program-name> = {
    enable = lib.mkEnableOption "<program-name>";
    theme = lib.mkOption {
      type = lib.types.str;
      default = "dark";
    };
  };

  config = lib.mkIf cfg.enable {
    home-manager.users.${config.user.name} = {
      programs.<program-name> = {
        enable = true;
        settings.theme = cfg.theme;
      };
    };
  };
}
```

**Key Points:**
- Maps to Home Manager `programs.*` options
- User-specific configuration
- Dotfiles, themes, plugins

## 4. Module Aspect

**Purpose:** Group related features into collections

**File Location:** `modules/modules/<module-name>.nix`

**Structure:**
```nix
{ config, lib, ... }:
let
  cfg = config.flake.modules.module.<module-name>;
in {
  options.flake.modules.module.<module-name> = {
    enable = lib.mkEnableOption "<module-name> suite";
  };

  config = lib.mkIf cfg.enable {
    # Enable multiple related features
    flake.modules.program.firefox.enable = true;
    flake.modules.program.thunderbird.enable = true;
    flake.modules.service.xserver.enable = true;
  };
}
```

**Key Points:**
- Enables multiple features as a group
- No direct NixOS/HM config, only feature activation
- Examples: "desktop-environment", "development-tools"

## 5. Class Aspect

**Purpose:** Define aspect types and shared behavior

**File Location:** `modules/classes/<aspect>.nix`

**Structure:**
```nix
{ lib, ... }:
{
  options.flake.modules.<aspect> = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        enable = lib.mkEnableOption "feature";
        # Shared options for all features of this aspect
      };
    });
    default = {};
    description = "Features of type <aspect>";
  };
}
```

**Key Points:**
- Defines the aspect's option structure
- One file per aspect type
- Rarely modified once established

## 6. Container Aspect

**Purpose:** Containerized applications (Docker/Podman)

**File Location:** `modules/containers/<container-name>.nix`

**Structure:**
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.flake.modules.container.<container-name>;
in {
  options.flake.modules.container.<container-name> = {
    enable = lib.mkEnableOption "<container-name>";
    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/<image>:<tag>";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.<container-name> = {
      image = cfg.image;
      ports = [ "${toString cfg.port}:8080" ];
      volumes = [ "/data:/data" ];
    };
  };
}
```

**Key Points:**
- Uses `virtualisation.oci-containers`
- Manages Docker/Podman containers
- Include port mappings, volumes, environment

## 7. VM Aspect

**Purpose:** Virtual machine definitions

**File Location:** `modules/vms/<vm-name>.nix`

**Structure:**
```nix
{ config, lib, ... }:
let
  cfg = config.flake.modules.vm.<vm-name>;
in {
  options.flake.modules.vm.<vm-name> = {
    enable = lib.mkEnableOption "<vm-name>";
    memory = lib.mkOption {
      type = lib.types.int;
      default = 2048;
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.libvirtd.enable = true;
    # VM-specific config
  };
}
```

**Key Points:**
- Defines QEMU/libvirt VMs
- Memory, CPU, disk configuration
- Network and storage settings

## 8. Secret Aspect

**Purpose:** Encrypted secrets (SOPS/age)

**File Location:** `modules/secrets/<secret-name>.nix`

**Structure:**
```nix
{ config, lib, ... }:
let
  cfg = config.flake.modules.secret.<secret-name>;
in {
  options.flake.modules.secret.<secret-name> = {
    enable = lib.mkEnableOption "<secret-name>";
    owner = lib.mkOption {
      type = lib.types.str;
      default = "root";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.<secret-name> = {
      sopsFile = ./../../secrets/<secret-name>.yaml;
      owner = cfg.owner;
    };
  };
}
```

**Key Points:**
- Uses SOPS for encryption
- Age keys for decryption
- Per-host key management

## Validation Rules

For each aspect, validate:

1. **File Location:** `modules/<aspect-plural>/<name>.nix`
2. **Module Class:** Uses appropriate class (nixos/darwin/homeManager/generic)
3. **Aspect Path:** `flake.modules.<class>.<name>`
4. **Import Pattern:** Features enable by default when imported
5. **No Conditional Imports:** Never use `lib.mkIf` with `imports`
6. **No Cross-Class:** Can't import nixos into darwin (use generic)
7. **lib.mkMerge:** Always use for merging, never `//`
8. **Single Purpose:** One feature per file
9. **No specialArgs:** Use let...in or flake-level options

**Complete validation checklist:** See [validation-rules.md](validation-rules.md)

## Common Anti-Patterns

**CRITICAL violations:**

1. **Conditional imports** - Using `lib.mkIf` with `imports`:
   ```nix
   # ❌ WRONG - causes recursion
   imports = lib.mkIf condition [ someModule ];
   ```

2. **Cross-class imports** - Importing wrong module class:
   ```nix
   # ❌ WRONG - nixos module into darwin
   flake.modules.darwin.myFeature = {
     imports = [ inputs.self.modules.nixos.other ];
   };
   ```

3. **Using // instead of lib.mkMerge** - Shallow merge loses config:
   ```nix
   # ❌ WRONG
   config = base // extra;
   
   # ✅ CORRECT
   config = lib.mkMerge [ base extra ];
   ```

4. **Enable options instead of import pattern** - Old module style:
   ```nix
   # ❌ WRONG - not dendritic
   options.myFeature.enable = lib.mkEnableOption "feature";
   config = lib.mkIf cfg.enable { ... };
   
   # ✅ CORRECT - dendritic pattern
   flake.modules.nixos.myFeature = {
     services.myapp.enable = true;  # Enabled by default
   };
   ```

**Design violations:**

- **Host defines options:** Hosts should import, not define features
- **Wrong aspect:** Service in programs/, program in services/
- **Multiple features per file:** Split into separate modules
- **Multiple imports:** Same module imported multiple times in path
- **Using specialArgs:** Use let...in or flake-level options instead

See [validation-rules.md](validation-rules.md) for complete anti-pattern catalog.

