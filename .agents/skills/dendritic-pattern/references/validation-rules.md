# Dendritic Validation Rules

## Critical Implementation Rules

These rules are **non-negotiable** for valid dendritic pattern code. Violations will cause errors or unexpected behavior.

### Rule 1: Module Classes Are Typed

Every module belongs to a **module class** that defines its configuration context.

**Standard Module Classes:**
- `nixos` - NixOS system configuration
- `darwin` - Nix-Darwin macOS configuration  
- `homeManager` - Home Manager user configuration
- `generic` - Platform-agnostic, importable into any class

**Structure:**
```nix
# Define aspect for specific class
flake.modules.<class>.<aspect-name> = {
  # Class-specific config here
};
```

**Examples:**
```nix
# NixOS service
flake.modules.nixos.nginx = {
  services.nginx.enable = true;
};

# Darwin service (different from NixOS)
flake.modules.darwin.nginx = {
  services.nginx.enable = true;
  # Darwin-specific settings
};

# Home Manager program
flake.modules.homeManager.firefox = {
  programs.firefox.enable = true;
};

# Generic (works in all contexts)
flake.modules.generic.constants = {
  options.myConstants = lib.mkOption { ... };
};
```

### Rule 2: NO Conditional Imports

**NEVER use `lib.mkIf` with `imports`** - it causes infinite recursion errors.

❌ **WRONG:**
```nix
{
  imports = lib.mkIf someCondition [
    inputs.self.modules.nixos.someFeature
  ];
}
```

✅ **CORRECT:**
```nix
{
  # Import unconditionally
  imports = [
    inputs.self.modules.nixos.someFeature
  ];
  
  # Make the CONTENT conditional
  config = lib.mkIf someCondition {
    # Feature content here
  };
}
```

**Why?** Nix evaluates imports to determine available options, but conditional imports create circular dependencies where the condition depends on imported options.

### Rule 3: NO Cross-Class Imports

Modules are typed by class. **Cannot import wrong class type.**

❌ **WRONG:**
```nix
# In darwin module
flake.modules.darwin.myFeature = {
  imports = [
    inputs.self.modules.nixos.someFeature  # ERROR: nixos → darwin
  ];
};
```

✅ **CORRECT - Use generic class:**
```nix
# Shared code in generic class
flake.modules.generic.sharedConfig = {
  # Platform-agnostic config
};

# Import generic into both
flake.modules.nixos.myFeature = {
  imports = [ inputs.self.modules.generic.sharedConfig ];
};

flake.modules.darwin.myFeature = {
  imports = [ inputs.self.modules.generic.sharedConfig ];
};
```

### Rule 4: NO Multiple Imports in Same Path

**Avoid importing same module multiple times in one hierarchy path.**

❌ **WRONG:**
```nix
flake.modules.nixos.hostA = {
  imports = [
    inputs.self.modules.nixos.baseSystem  # Imports nginx
    inputs.self.modules.nixos.nginx       # Imported again!
  ];
};
```

✅ **CORRECT:**
```nix
flake.modules.nixos.hostA = {
  imports = [
    inputs.self.modules.nixos.baseSystem  # Imports nginx
    # Don't import nginx again
  ];
};
```

**Exception:** Multi-Context Aspect with home-manager.sharedModules requires careful handling:
```nix
# In gnome feature
flake.modules.nixos.gnome = {
  home-manager.sharedModules = [
    inputs.self.modules.homeManager.gnome
  ];
};

# When inheriting, DON'T add to sharedModules again
flake.modules.nixos.gnome-tweaked = {
  imports = [ inputs.self.modules.nixos.gnome ];
  # Don't add to sharedModules again - already in parent
};
```

### Rule 5: MUST Use lib.mkMerge for Attribute Sets

**ALWAYS use `lib.mkMerge`** instead of `//` when merging attribute sets.

❌ **WRONG:**
```nix
config = baseConfig // additionalConfig;  # Shallow merge!
```

✅ **CORRECT:**
```nix
config = lib.mkMerge [
  baseConfig
  additionalConfig
  (lib.mkIf condition { ... })
];
```

**Applies to:**
- Merging factory aspect outputs with customizations
- Merging DRY aspects
- Combining conditional configurations
- Merging collector aspect contributions

**Why?** The `//` operator does shallow merge and overwrites nested attributes. `lib.mkMerge` does deep recursive merge.

### Rule 6: Features Enable by Default (No enable = true)

**Features activate when imported**, not via enable options.

❌ **OLD PATTERN (not dendritic):**
```nix
# Feature defines option
options.services.myapp.enable = lib.mkEnableOption "myapp";

# User must enable
config.services.myapp.enable = true;
```

✅ **DENDRITIC PATTERN:**
```nix
# Feature enables directly
flake.modules.nixos.myapp = {
  services.myapp.enable = true;  # Enabled by default
  services.myapp.port = lib.mkDefault 8080;  # User can override
};

# User just imports
flake.modules.nixos.myHost = {
  imports = [ inputs.self.modules.nixos.myapp ];  # Enabled!
};
```

**Why?** Importing a feature signals intent to use it. Using `lib.mkDefault` allows hosts to override defaults without complex option systems.

## Important Implementation Patterns

### Collector Aspect: Multiple Files, Same Name

**Multiple features can define the same aspect name** - configs merge automatically.

```nix
# In syncthing feature
flake.modules.nixos.syncthing = {
  services.syncthing.enable = true;
};

# In host1 feature - SAME ASPECT NAME
flake.modules.nixos.syncthing = {
  services.syncthing.settings.devices.host1 = {
    id = "ABC-123-DEF";
  };
};

# In host2 feature - SAME ASPECT NAME  
flake.modules.nixos.syncthing = {
  services.syncthing.settings.devices.host2 = {
    id = "XYZ-789-GHI";
  };
};

# Result: All three merge together!
```

**When both hosts import syncthing**, all device IDs are available on both hosts.

### Factory Aspect: Function Library

Factory functions stored in `config.flake.factory.<name>`.

**Define factory library:**
```nix
{
  options.flake.factory = lib.mkOption {
    type = lib.types.attrsOf lib.types.unspecified;
    default = {};
  };
  
  config.flake.factory.user = username: isAdmin: {
    # Returns flake.modules attribute set
    nixos."${username}" = {
      users.users."${username}".name = username;
      users.users."${username}".extraGroups = lib.optionals isAdmin ["wheel"];
    };
  };
}
```

**Use factory:**
```nix
{
  flake.modules = lib.mkMerge [
    (inputs.self.factory.user "alice" true)
    {
      nixos.alice = {
        # Additional customization
      };
    }
  ];
}
```

### Multi-Context: Auxiliary Modules

Private modules for nested contexts (e.g., Home Manager within NixOS).

```nix
{
  # Main module (NixOS)
  flake.modules.nixos.gnome = {
    # Include auxiliary module in Home Manager
    home-manager.sharedModules = [
      inputs.self.modules.homeManager.gnome
    ];
    
    # NixOS system-level config
    services.xserver.desktopManager.gnome.enable = true;
  };
  
  # Auxiliary module (Home Manager)
  flake.modules.homeManager.gnome = {
    # Home Manager user-level config
    dconf.settings = { ... };
  };
}
```

### Alternative to specialArgs

**Don't use specialArgs** - use these patterns instead:

**Pattern 1: let...in at feature level**
```nix
{
  let
    sharedValue = "example.com";
  in {
    flake.modules.nixos.service1 = {
      services.nginx.serverName = sharedValue;
    };
    
    flake.modules.nixos.service2 = {
      services.apache.serverName = sharedValue;
    };
  }
}
```

**Pattern 2: Flake-level options**
```nix
{
  # Define at flake level
  options.myDomain = lib.mkOption {
    type = lib.types.str;
    default = "example.com";
  };
  
  config.myDomain = "example.com";
  
  # Access in modules via inputs.self
  flake.modules.nixos.service = {
    services.nginx.serverName = inputs.self.myDomain;
  };
}
```

## File Organization Rules

### Underscore Prefix Exclusion

Files/folders starting with `_` are **excluded from auto-import**.

```
modules/
  ├── nginx.nix           # Imported
  ├── _postgres.nix       # NOT imported (WIP)
  └── _experimental/      # NOT imported (testing)
      └── feature.nix
```

Use for:
- Work-in-progress features
- Disabled/experimental code
- Template files
- Documentation

### File Naming Conventions

Optional but recommended from Comprehensive Example:

**Brackets indicate platform usage:**
- `[N]` - NixOS only
- `[D]` - Darwin only  
- `[ND]` - NixOS and Darwin
- `[n]` - Home Manager on NixOS
- `[d]` - Home Manager on Darwin
- `[nd]` - Home Manager on both

**Example:**
```
modules/
  ├── hosts/
  │   ├── server [N]/
  │   └── macbook [D]/
  ├── programs/
  │   ├── firefox [nd]/
  │   └── safari [d]/
  └── services/
      └── nginx [N]/
```

## Validation Checklist

When reviewing a dendritic module:

- [ ] Module defines `flake.modules.<class>.<aspect>`
- [ ] No `lib.mkIf` used with `imports`
- [ ] No cross-class imports (or uses `generic` class)
- [ ] No duplicate imports in hierarchy
- [ ] Uses `lib.mkMerge` not `//` for merging
- [ ] Features enable by default, use `lib.mkDefault` for overrides
- [ ] Factory functions in `config.flake.factory.*`
- [ ] Auxiliary modules via `home-manager.sharedModules`
- [ ] No `specialArgs` usage
- [ ] WIP files prefixed with `_`
