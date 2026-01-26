# Dendritic Pattern FAQ

## General Questions

### What problem does dendritic solve?

Traditional NixOS configurations become tangled "monoliths" where:
- Host configs mix machine-specific settings with reusable features
- Services are copy-pasted between machines
- Changes to one feature affect unrelated hosts
- It's hard to share configurations between systems

Dendritic solves this by:
- Separating features from hosts
- Making features reusable building blocks
- Providing clear organizational patterns
- Enabling composition over inheritance

### Why use flake-parts?

Flake-parts provides:
- **Module system for flakes:** Organize flake outputs as modules
- **Auto-import:** Automatically discover and load modules
- **Pervasive options:** Define options accessible across all modules
- **Type safety:** Validate configuration at eval time

Without flake-parts, you'd need to manually import every module and wire up all the connections.

### What's the difference between aspect and class?

- **Aspect:** A category of features (host, service, program, etc.)
- **Class:** The module that defines an aspect's structure (`modules/classes/service.nix`)

Think of it like OOP: class is the definition, aspect is the concept.

## Design Decisions

### Why flake.modules.<aspect>.<feature>?

This structure:
- Makes feature options accessible across all modules
- Follows flake-parts pervasive options pattern
- Enables aspect-oriented composition
- Provides clear namespacing

Alternative `config.my.features.<aspect>.<feature>` would be NixOS-specific and not accessible in flake-level modules.

### Why separate modules/<aspect>/ directories?

Separation by aspect provides:
- **Clear organization:** Find service features in `modules/services/`
- **Scalability:** Add 100 services without clutter
- **Aspect validation:** Easy to check if service follows service patterns
- **IDE navigation:** Jump to feature by directory

### Why one feature per file?

One-to-one mapping provides:
- **Single responsibility:** Each file has one clear purpose
- **Easy refactoring:** Move/delete features without conflicts
- **Clear dependencies:** Import graph shows feature relationships
- **Git-friendly:** Clean diffs when features change

### Should every module have an enable option?

**Yes.** Every feature should have `enable = lib.mkEnableOption` because:
- Hosts enable features declaratively
- Disabled features don't evaluate (faster rebuilds)
- Clear intent: "this machine has nginx" vs inherited defaults
- Easy to toggle for testing

Exception: Class modules that only define option structure.

### When to use module aspect vs just enabling features?

Use **module aspect** when:
- Multiple features always go together (desktop environment)
- You want a named "bundle" (development-tools, media-server)
- Features are related conceptually

Use **direct feature enabling** when:
- Features are independent
- One-off feature for specific host
- Host needs custom configuration of feature

## Implementation Questions

### How do features access other features' options?

Through the shared `config.flake.modules.*` namespace:

```nix
# modules/services/app.nix
{ config, lib, ... }:
let
  cfg = config.flake.modules.service.app;
  nginxCfg = config.flake.modules.service.nginx;
in {
  config = lib.mkIf cfg.enable {
    # Use nginx's port configuration
    services.app.proxy = "http://localhost:${toString nginxCfg.port}";
  };
}
```

### How do I override feature defaults per host?

In the host file:

```nix
# modules/hosts/my-machine.nix
{
  flake.modules.service.nginx = {
    enable = true;
    port = 8080;  # Override default
    virtualHosts."example.com".enable = true;
  };
}
```

### Can features depend on other features?

Yes, through implicit dependencies:

```nix
# modules/services/app.nix
config = lib.mkIf cfg.enable {
  # Auto-enable nginx when app is enabled
  flake.modules.service.nginx.enable = lib.mkDefault true;
  flake.modules.service.nginx.port = 80;
}
```

Use `lib.mkDefault` so host can override.

### Where do machine-specific files go?

In `machines/<hostname>/`:
- `configuration.nix` - Hardware, filesystems, boot
- `hardware-configuration.nix` - Auto-generated hardware config
- `secrets/` - Host-specific secrets

Host modules in `modules/hosts/<hostname>.nix` reference these:

```nix
{
  flake.nixosConfigurations.my-machine = {
    modules = [ ./../../machines/my-machine/configuration.nix ];
  };
}
```

### How do I share options between aspects?

Define shared options in a class module:

```nix
# modules/classes/common.nix
{
  options.flake.common = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "example.com";
    };
  };
}
```

Access in any feature:
```nix
config.services.nginx.serverName = config.flake.common.domain;
```

## Migration Questions

### How do I migrate existing NixOS config?

1. **Extract features:** Identify reusable chunks (nginx, firefox, postgresql)
2. **Create aspect modules:** Move each feature to `modules/<aspect>/<name>.nix`
3. **Add options:** Wrap in `options.flake.modules.<aspect>.<name>`
4. **Update host:** Enable features in `modules/hosts/<hostname>.nix`
5. **Test:** `nixos-rebuild build --flake .#<hostname>`

### Can I use dendritic with non-flake configs?

No. Dendritic requires flake-parts, which requires flakes.

But you can:
1. Convert config to flake format
2. Add flake-parts
3. Gradually extract features into dendritic pattern

### Do I need to use all 8 aspects?

No. Start with what you need:
- **Minimum:** host, service, program
- **Common:** + container, secret
- **Advanced:** + module, vm, class

## Troubleshooting

### Error: "infinite recursion encountered"

**Cause:** Circular dependency between modules, often from:
- Module reads `cfg.enable` while also setting options that affect `cfg`
- Two features each try to enable the other

**Fix:**
- Remove outer `lib.mkIf cfg.enable` wrapper around all config
- Add `lib.mkIf` only to specific config sections
- Use `lib.mkDefault` for suggested dependencies

### Error: "option ... is used but not defined"

**Cause:** Feature options not exported or wrong path.

**Fix:**
- Check option path: `options.flake.modules.<aspect>.<name>`
- Ensure class module defines aspect: `modules/classes/<aspect>.nix`
- Verify import-tree is loading the module

### Features not taking effect

**Cause:** Feature imported but config not applied.

**Check:**
- Is feature imported in host's `imports` list?
- Are there syntax errors? Run `nix flake check`
- Is import-tree loading the module? Check if file starts with `_`
- Does feature enable services by default? (Should not need enable option)

## Practical Tips

### Finding dendritic code examples

**GitHub search tip:**
```
lang:nix flake.modules <OPTION-NAME>
```

Example: `lang:nix flake.modules services.nginx` finds dendritic nginx implementations.

### Quick validation commands

Check your flake structure:
```bash
# Check for errors
nix flake check

# Show loaded modules (if debug output configured)
nix eval .#debug.loadedModules

# Test build without switching
nixos-rebuild build --flake .#<hostname>
```

### Common gotchas

1. **Forgot `lib.mkMerge`:** Using `//` causes shallow merge and lost config
2. **Conditional imports:** Causes infinite recursion - make content conditional instead
3. **Wrong module class:** Can't import nixos into darwin - use generic class
4. **Multiple imports:** Same feature imported multiple times causes duplicate definitions
5. **Missing `inputs.self`:** Must use `inputs.self.modules.<class>.<aspect>` for imports

### Migration strategy

1. **Start small:** Convert one service/program to dendritic pattern
2. **Test thoroughly:** Ensure feature works in isolation
3. **Extract gradually:** Move features one at a time
4. **Keep old config:** Don't delete until new pattern proven
5. **Document decisions:** Note why each feature uses specific patterns

### Reference repositories

Study these for real-world examples:
- [vic/vix](https://github.com/vic/vix)
- [drupol/infra](https://github.com/drupol/infra)
- [mightyiam/infra](https://github.com/mightyiam/infra)
- [Doc-Steve/dendritic-design-with-flake-parts](https://github.com/Doc-Steve/dendritic-design-with-flake-parts)

