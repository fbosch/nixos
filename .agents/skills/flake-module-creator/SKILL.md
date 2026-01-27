---
name: flake-module-creator
description: Create new NixOS, Darwin, or Home Manager modules following the dendritic flake pattern. Use when the user wants to add a new feature module (service, program, system configuration, etc.) to their flake. Triggers include requests like "add [feature] module", "create a module for [feature]", "set up [feature] in the flake", or "add nginx/git/firefox/etc."
---

# Flake Module Creator

Create new NixOS, Darwin, or Home Manager modules following the dendritic pattern with flake-parts.

## Module Design Mindset

Before creating any module, ask yourself:

1. **Scope**: Is this ONE feature or multiple features bundled together?
   - If multiple → Split into separate modules
   - If unclear → Start narrow, expand later

2. **Context**: Where does this feature live?
   - System-level only (NixOS/Darwin) → Single class module
   - User-level only (Home Manager) → Single class module  
   - Both system + user → Multi-context module

3. **Sharing**: How many hosts will use this?
   - One host → Options can be minimal or none
   - Multiple hosts with variations → Define options with `lib.mkDefault`
   - All hosts identically → No options needed

4. **Dependencies**: What does this feature require?
   - Other modules → Import via `config.flake.modules`
   - Secrets → SOPS integration required
   - Nothing → Standalone module

5. **Lifetime**: Is this stable or experimental?
   - Stable → Normal filename
   - Work-in-progress → Prefix with `_` to exclude from auto-import

## Core Principles (CRITICAL)

These rules are non-negotiable for valid dendritic code:

1. **Module Classes**: Every module belongs to `nixos`, `darwin`, `homeManager`, or `generic`
2. **NO Conditional Imports**: Never use `lib.mkIf` with `imports` (causes recursion)
3. **NO Cross-Class Imports**: Can't import nixos module into darwin (use generic class)
4. **MUST Use lib.mkMerge**: Always use `lib.mkMerge` not `//` for merging
5. **Import to Enable**: Features activate when imported, not via enable options
6. **Collector Merging**: Multiple files can define same aspect name - configs merge

See [../dendritic-pattern/references/validation-rules.md](../dendritic-pattern/references/validation-rules.md) for complete details.

## Workflow

### 1. Determine Module Information

Ask the user for:

- **Feature name** (e.g., "nginx", "firefox", "git")
- **Module type**: NixOS service, Home Manager program, system config, etc.
- **Module class**: `nixos`, `homeManager`, `darwin`, or `generic`
- **Category**: Where it belongs (services, applications, development, system, etc.)
- **Configuration details**:
  - Options to expose (ports, paths, settings)
  - Default values
  - Dependencies on other modules
  - Whether it needs secrets (SOPS integration)

### 2. Choose Module Pattern

Based on the feature, select the appropriate pattern:

**Simple Module** - Single-purpose feature for one context
- Example: A NixOS service, a Home Manager program
- File: `modules/<category>/<name>.nix`
- Exports: `flake.modules.nixos."<category>/<name>"`

**Multi-Context Module** - Feature spanning NixOS + Home Manager
- Example: GNOME (system packages + user settings)
- Files: Same file exports both classes
- Exports: Both `flake.modules.nixos.<name>` and `flake.modules.homeManager.<name>`

**Collector Module** - Aggregates config from multiple sources
- Example: Syncthing devices across hosts
- Multiple files export same aspect name
- Configs merge automatically

**Generic Module** - Platform-agnostic, importable anywhere
- Example: Constants, shared configurations
- File: `modules/<category>/<name>.nix`
- Exports: `flake.modules.generic.<name>`

See [references/module-patterns.md](references/module-patterns.md) for detailed patterns.

### 3. Load Template and Create Module File

**MANDATORY**: Based on module type, load the appropriate template:

**For NixOS Services**:
MUST read [assets/nixos-service-template.nix](assets/nixos-service-template.nix)

**For Containerized Services**:
MUST read [assets/containerized-service-template.nix](assets/containerized-service-template.nix)

**For Home Manager Programs**:
MUST read [assets/home-manager-program-template.nix](assets/home-manager-program-template.nix)

**For System Configuration**:
MUST read [assets/system-config-template.nix](assets/system-config-template.nix)

**For Multi-Context Modules**:
MUST read [assets/multi-context-template.nix](assets/multi-context-template.nix)

**For Generic Modules**:
MUST read [assets/generic-template.nix](assets/generic-template.nix)

**Do NOT load** [references/sops-integration.md](references/sops-integration.md) unless module explicitly needs secrets.

**Do NOT load** [references/module-patterns.md](references/module-patterns.md) unless user asks about patterns or you need clarification.

**File Location**: `modules/<category>/<name>.nix`

Replace template placeholders:
- `<SERVICE-NAME>` / `<PROGRAM-NAME>` / `<NAME>` → actual feature name
- `<PACKAGE-NAME>` → nixpkgs package name
- `<IMAGE>` / `<TAG>` → container image details
- `<category>` → services, applications, development, etc.

### 4. Handle Dependencies

**Import other modules**:
```nix
{ config, ... }:
{
  flake.modules.nixos."services/myapp" = {
    imports = [
      config.flake.modules.nixos."virtualization/podman"
    ];
  };
}
```

**Reference flake metadata**:
```nix
let
  synologyDomain = config.flake.meta.synology.domain;
in {
  services.myapp.url = "https://app.${synologyDomain}";
}
```

### 5. Handle Secrets (SOPS)

If the module needs secrets, **load [references/sops-integration.md](references/sops-integration.md)** for complete patterns.

Basic pattern:
```nix
config = lib.mkIf cfg.enable {
  sops.secrets.myapp-token = {
    mode = "0400";
    owner = cfg.user;
  };
  
  services.myapp.tokenFile = config.sops.secrets.myapp-token.path;
};
```

### 6. Add to Host Configuration

Guide the user to import the new module:

**Via host module imports**:
```nix
# In modules/hosts/<hostname>.nix
imports = config.flake.lib.resolve [
  "services/myapp"
];
```

**Override defaults if needed**:
```nix
services.myapp.port = 9090;
```

## Dendritic-Specific Edge Cases

### Edge Case 1: Collector Pattern Conflicts

**Problem**: Two modules define same aspect with conflicting values

```nix
# Module A
flake.modules.nixos.myapp = { services.myapp.port = 8080; };

# Module B  
flake.modules.nixos.myapp = { services.myapp.port = 9090; };
```

**Result**: Last import wins, but order is undefined in flake-parts

**Fix**: Use `lib.mkDefault` in base module, override in host:
```nix
# Base module (modules/services/myapp.nix)
flake.modules.nixos.myapp = {
  services.myapp.port = lib.mkDefault 8080;
};

# Collector in host file (modules/hosts/server.nix)
flake.modules.nixos.myapp = {
  services.myapp.extraConfig = "...";  # Add, don't override port
};

# Host override (in host imports section, NOT collector)
services.myapp.port = 9090;  # Override default
```

**Why this matters**: Collector merging is for additive config (devices, hosts, routes), not for overriding values.

### Edge Case 2: Multi-Context Module Inheritance Trap

**Problem**: Inheriting multi-context module duplicates Home Manager import

```nix
# Base module
flake.modules.nixos.gnome = {
  services.xserver.desktopManager.gnome.enable = true;
  
  home-manager.sharedModules = [
    config.flake.modules.homeManager.gnome  # HM module included here
  ];
};

# Inherited module - WRONG
flake.modules.nixos.gnome-tweaked = {
  imports = [ config.flake.modules.nixos.gnome ];
  
  # DON'T add to sharedModules again!
  # home-manager.sharedModules = [ ... ];  # Already inherited from parent!
};
```

**Why this fails**: 
- Parent already includes Home Manager module in `sharedModules`
- Inheritance brings `sharedModules` along
- Adding again causes duplicate module imports
- Results in "duplicate definition" errors for Home Manager options

**Correct approach**: Only add to `sharedModules` in base module, never in inheritors.

### Edge Case 3: Conditional Config vs Conditional Imports

**Problem**: Confusing when to use `lib.mkIf` 

```nix
# ❌ WRONG - Conditional imports cause recursion
{
  imports = lib.mkIf someCondition [
    config.flake.modules.nixos.someFeature
  ];
}

# ✅ CORRECT - Always import, make CONTENT conditional
{
  imports = [
    config.flake.modules.nixos.someFeature
  ];
  
  config = lib.mkIf someCondition {
    services.someFeature.extraConfig = "...";
  };
}
```

**Why conditional imports fail**:
- Nix evaluates `imports` to determine available options
- Condition may depend on options from imported module
- Creates circular dependency: "need options to evaluate condition, need condition to import options"
- Results in infinite recursion error

**The rule**: `imports` is always unconditional. Use `lib.mkIf` in `config` block instead.

### Edge Case 4: lib.mkMerge vs // Operator

**Problem**: Using `//` for merging seems simpler, but breaks nested configs

```nix
# ❌ WRONG - Shallow merge loses data
let
  baseConfig = { 
    services.nginx.virtualHosts.siteA = { ... };
  };
  extraConfig = { 
    services.nginx.virtualHosts.siteB = { ... };
  };
in
  baseConfig // extraConfig
  
# Result: Only siteB exists! siteA was overwritten!
```

**Why this breaks**:
- `//` does shallow merge: overwrites entire attribute at first level
- `baseConfig.services.nginx.virtualHosts` = `{ siteA = {...}; }`
- `extraConfig.services.nginx.virtualHosts` = `{ siteB = {...}; }`
- `//` replaces entire `virtualHosts` attribute, deleting siteA

**Correct approach**:
```nix
# ✅ CORRECT - Deep merge preserves all data
lib.mkMerge [
  baseConfig
  extraConfig
  (lib.mkIf condition { ... })
]

# Result: Both siteA and siteB exist
```

**When to use what**:
- `lib.mkMerge` - Always use for NixOS/Home Manager configs (deep merge)
- `//` - Only for flat attribute sets with no nested structures

### Edge Case 5: Options Without lib.mkDefault

**Problem**: Hard-coded values prevent host overrides

```nix
# ❌ WRONG - Can't override
flake.modules.nixos.myapp = {
  services.myapp.port = 8080;  # Fixed value
};

# In host config:
services.myapp.port = 9090;
# Error: "The option `services.myapp.port` is defined multiple times"
```

**Why this fails**: NixOS treats both as definitions at same priority, conflicts.

**Fix**:
```nix
# ✅ CORRECT - Host can override
flake.modules.nixos.myapp = {
  services.myapp.port = lib.mkDefault 8080;  # Default value
};

# In host config:
services.myapp.port = 9090;  # Override works!
```

**Priority hierarchy**:
- `lib.mkOverride 10` - Highest priority
- Regular definition - High priority (what hosts use)
- `lib.mkDefault` - Low priority (what modules use)
- `lib.mkOverride 1500` - Lowest priority

**The rule**: Modules use `lib.mkDefault`, hosts use regular definitions.

## NEVER Do When Creating Modules

**NEVER use enable options in dendritic pattern**

```nix
# ❌ WRONG - This is NOT the dendritic way
options.myapp.enable = lib.mkEnableOption "myapp";
config = lib.mkIf cfg.enable { ... };
```

**Why this is wrong**:
- Breaks dendritic import-to-enable contract
- Requires two actions: import + enable (cognitive overhead)
- Can't use collector pattern (multiple files defining same aspect)
- Contradicts flake-parts philosophy of composition via imports
- Forces every consumer to write boilerplate: `myapp.enable = true;`

**Exception**: Containerized services conventionally use `enable` option (see termix.nix example). This is because container lifecycle (start/stop) is heavier than package installation.

---

**NEVER import auxiliary modules directly**

```nix
# ❌ WRONG - Importing Home Manager module in NixOS context
imports = config.flake.lib.resolve [
  "desktop/gnome"  # NixOS module (OK)
  "desktop/gnome"  # Trying to import HM module too (WRONG)
];
```

**Why this fails**: 
- Home Manager modules expect HM context (access to `home.*` options)
- NixOS context doesn't have `home.*` options
- Results in "option does not exist" errors
- Auxiliary modules are private - only imported via `home-manager.sharedModules`

**Correct approach**: Only import via `sharedModules` in parent module.

---

**NEVER use `//` for merging configs**

See Edge Case 4 above for detailed explanation.

---

**NEVER define options without `lib.mkDefault`**

See Edge Case 5 above for detailed explanation.

---

**NEVER use conditional imports**

See Edge Case 3 above for detailed explanation.

---

**NEVER import modules from different classes**

```nix
# ❌ WRONG - Importing NixOS module into Darwin
flake.modules.darwin.myFeature = {
  imports = [ config.flake.modules.nixos.someFeature ];  # ERROR
};
```

**Why this fails**:
- Module classes are typed contexts
- NixOS modules use `services.*`, `systemd.*`, `boot.*` (Linux-specific)
- Darwin modules use different service system, no systemd, no Linux boot
- Results in "option does not exist" errors

**Fix**: Use `generic` class for shared code:
```nix
# Shared in generic class
flake.modules.generic.sharedConfig = { ... };

# Import into both
flake.modules.nixos.myFeature = {
  imports = [ config.flake.modules.generic.sharedConfig ];
};

flake.modules.darwin.myFeature = {
  imports = [ config.flake.modules.generic.sharedConfig ];
};
```

---

**NEVER use specialArgs for passing values**

```nix
# ❌ WRONG - Using specialArgs
specialArgs = { myDomain = "example.com"; };
```

**Why this is wrong**:
- Not dendritic (breaks declarative tree structure)
- Can't see where values come from (invisible data flow)
- Can't override at flake level
- Discourages use of `config.flake.meta`

**Fix - Use flake metadata**:
```nix
# At flake level
config.flake.meta.domain = "example.com";

# In modules
services.myapp.url = "https://app.${config.flake.meta.domain}";
```

## Validation Checklist

Before finalizing the module, verify:

- [ ] Module exports under `flake.modules.<class>.<name>`
- [ ] Module class is correct (nixos/darwin/homeManager/generic)
- [ ] No `lib.mkIf` used with `imports`
- [ ] No cross-class imports (or uses `generic` class for sharing)
- [ ] Uses `lib.mkMerge` not `//` for merging
- [ ] Features enable by default when imported (no enable option unless containerized)
- [ ] Uses `lib.mkDefault` for all user-overridable values
- [ ] Dependencies imported via `config.flake.modules`
- [ ] No `specialArgs` usage
- [ ] File location matches: `modules/<category>/<name>.nix`
- [ ] Aspect name matches semantic purpose
- [ ] If multi-context, auxiliary module only in `sharedModules`, never imported directly

## Reference Documentation

Load these references only when explicitly needed:

- **[../dendritic-pattern/references/validation-rules.md](../dendritic-pattern/references/validation-rules.md)** - Complete validation rules (load if uncertain about any rule)
- **[../dendritic-pattern/references/aspect-patterns.md](../dendritic-pattern/references/aspect-patterns.md)** - 8 aspect patterns catalog (load if pattern selection unclear)
- **[../dendritic-pattern/references/basics.md](../dendritic-pattern/references/basics.md)** - Core dendritic concepts (load if user asks "what is dendritic")
- **[references/module-patterns.md](references/module-patterns.md)** - Detailed module creation patterns (load for complex scenarios)
- **[references/sops-integration.md](references/sops-integration.md)** - **LOAD WHEN SECRETS NEEDED** - Complete SOPS patterns

## Safety

- Ask user for confirmation before creating files
- Validate module structure against dendritic rules
- Check for existing modules with similar names using glob/grep
- Suggest appropriate category and naming conventions
- Warn about common anti-patterns if user's requirements suggest them
