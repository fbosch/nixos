# Dendritic Pattern Basics

## What is Dendritic?

Dendritic is an opinionated file organization pattern for NixOS flakes using flake-parts. It structures configurations as reusable, composable "features" organized by aspect-oriented design patterns.

## Core Concepts

### Module Classes

Every dendritic module belongs to a **module class** that defines its configuration context:

- **nixos** - NixOS system configuration (`services.*`, `networking.*`, etc.)
- **darwin** - Nix-Darwin macOS configuration (`system.*`, macOS services)
- **homeManager** - Home Manager user configuration (`programs.*`, `home.*`)
- **generic** - Platform-agnostic, can be imported into any class

Modules are typed by class and **cannot cross-import** (e.g., nixos module cannot import darwin module). Use `generic` class for shared code.

### Features as Building Blocks

A **feature** is a standalone, reusable configuration unit that:
- Implements ONE specific capability (e.g., "nginx reverse proxy", "PostgreSQL database", "Firefox browser")
- Is self-contained with its own options, defaults, and config
- Can define multiple aspects (one per module class)
- Follows one of 8 aspect patterns
- **Enables by default when imported** (not via enable options)

### File Organization

```
flake.nix                    # Root flake with flake-parts
modules/
  ├── classes/               # Feature classification
  │   ├── host.nix          # Host definitions
  │   ├── service.nix       # Service features
  │   └── program.nix       # Program features
  ├── hosts/                # Host-specific configs
  │   └── my-machine.nix    # Composes features
  ├── services/             # Service features
  │   └── nginx.nix         # Aspect-based module
  └── programs/             # Program features
      └── firefox.nix       # Aspect-based module
```

### Flake-Parts Integration

Dendritic uses flake-parts' `imports` to auto-load modules:

```nix
# flake.nix
{
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
    ./modules  # Auto-imports all modules
  ];
}
```

Modules are imported via `import-tree` pattern:

```nix
# modules/default.nix
{
  imports = lib.import-tree {
    paths = [ ./. ];
    args = { inherit inputs outputs; };
  };
}
```

### Module Structure

Every feature module defines aspects using `flake.modules.<class>.<aspect>`:

```nix
# modules/services/nginx.nix
{ lib, config, inputs, ... }:
{
  # Define nixos aspect
  flake.modules.nixos.nginx = {
    services.nginx.enable = true;  # Enabled by default!
    services.nginx.port = lib.mkDefault 80;  # User can override
  };
  
  # Define darwin aspect (same feature, different platform)
  flake.modules.darwin.nginx = {
    services.nginx.enable = true;
    services.nginx.port = lib.mkDefault 80;
  };
}
```

**Key differences from traditional modules:**
- No `enable` option - features activate when imported
- Use `lib.mkDefault` for user-overridable values
- Multiple aspects per feature (one per platform)
- Reference with `inputs.self.modules.<class>.<aspect>`

### Import Rules (CRITICAL)

Three non-negotiable rules:

1. **NO conditional imports** - Never use `lib.mkIf` with `imports`:
   ```nix
   # ❌ WRONG
   imports = lib.mkIf condition [ someModule ];
   
   # ✅ CORRECT
   imports = [ someModule ];
   config = lib.mkIf condition { ... };
   ```

2. **NO cross-class imports** - Can't import nixos into darwin:
   ```nix
   # ❌ WRONG
   flake.modules.darwin.myFeature = {
     imports = [ inputs.self.modules.nixos.other ];
   };
   
   # ✅ CORRECT - use generic class
   flake.modules.generic.shared = { ... };
   flake.modules.darwin.myFeature = {
     imports = [ inputs.self.modules.generic.shared ];
   };
   ```

3. **MUST use lib.mkMerge** - Never use `//` for merging:
   ```nix
   # ❌ WRONG
   config = base // extra;
   
   # ✅ CORRECT
   config = lib.mkMerge [ base extra ];
   ```

See [validation-rules.md](validation-rules.md) for complete details.

### Host Composition

Hosts import features to enable them:

```nix
# modules/hosts/my-machine.nix
{ inputs, ... }:
{
  flake.modules.nixos.my-machine = {
    imports = with inputs.self.modules.nixos; [
      nginx      # Imported = enabled!
      firefox
      postgresql
    ];
    
    # Override defaults if needed
    services.nginx.port = 8080;
  };
  
  # Boilerplate to create nixosConfiguration
  flake.nixosConfigurations.my-machine = {
    system = "x86_64-linux";
    modules = [
      ./../../machines/my-machine/configuration.nix
      inputs.self.modules.nixos.my-machine
    ];
  };
}
```

## File Organization Best Practices

### Underscore Prefix Exclusion

Files/folders starting with `_` are **excluded from auto-import**:

```
modules/
  ├── nginx.nix           # ✅ Imported
  ├── _postgres.nix       # ❌ NOT imported (WIP)
  └── _experimental/      # ❌ NOT imported
```

Use for work-in-progress, disabled, or experimental code.

### Optional Naming Conventions

Brackets indicate platform usage (from comprehensive example):
- `[N]` - NixOS only
- `[D]` - Darwin only
- `[ND]` - NixOS and Darwin
- `[n]` - Home Manager on NixOS
- `[d]` - Home Manager on Darwin

Example:
```
modules/
  ├── hosts/
  │   ├── server [N]/
  │   └── macbook [D]/
  └── programs/
      ├── firefox [nd]/
      └── safari [d]/
```

## Key Principles

1. **Feature = Module** - Each feature is a self-contained Nix module
2. **Aspect-Oriented** - Features follow 8 standard aspect patterns (see aspect-patterns.md)
3. **Flake-Parts Native** - Uses `flake.modules.<class>.<aspect>` structure
4. **Module Classes** - nixos, darwin, homeManager, generic
5. **Import to Enable** - No enable options, importing activates feature
6. **Auto-Import** - Modules discovered automatically via import-tree
7. **Host as Composer** - Hosts import features, don't define them
8. **Single Responsibility** - One feature, one file, one purpose

## Validation Checklist

- [ ] Module defines `flake.modules.<class>.<aspect>`
- [ ] Uses correct module class (nixos/darwin/homeManager/generic)
- [ ] No `lib.mkIf` used with `imports`
- [ ] No cross-class imports (or uses generic)
- [ ] Uses `lib.mkMerge` not `//` for merging
- [ ] Features enable by default (no enable options)
- [ ] File location organized logically
- [ ] Each feature has single clear purpose
- [ ] WIP files prefixed with `_`

For complete validation rules, see [validation-rules.md](validation-rules.md).
