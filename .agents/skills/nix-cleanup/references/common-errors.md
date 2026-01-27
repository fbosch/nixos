# Common Lint Error Patterns

This document catalogs common lint errors in this dendritic flake and how to resolve them.

## Statix Errors

### E001: "Consider using mkEnableOption"

**Example**:
```nix
# Statix flags this
options.services.myapp = {
  enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
  };
};
```

**Statix suggests**:
```nix
enable = lib.mkEnableOption "myapp";
```

**Resolution**: **REJECT** - This contradicts dendritic import-to-enable pattern.

**Why**: Dendritic modules enable by default when imported. Using `mkEnableOption` would:
- Set `default = false`
- Require explicit `myapp.enable = true;` in hosts
- Break import-to-enable contract

**Exception**: Containerized services in `services/containers/` use enable options.

---

### E002: "Manual inherit"

**Example**:
```nix
{ inputs, ... }:
let
  inherit (inputs) self nixpkgs;
in
  # ...
```

**Statix suggests**: Remove manual inherit

**Resolution**: 
- **In loader files** (`modules/flake-parts/`): KEEP - Explicit for clarity
- **In feature modules**: Safe to apply if truly redundant

---

### E003: "Empty let expression"

**Example**:
```nix
let
in {
  # config
}
```

**Resolution**: Safe to auto-fix everywhere

**Fix**: Remove empty let block

---

### E004: "Legacy let syntax"

**Example**:
```nix
rec {
  a = 1;
  b = a + 1;
}
```

**Resolution**: 
- Safe in feature modules
- Review in loader files

**Fix**:
```nix
let
  a = 1;
  b = a + 1;
in { inherit a b; }
```

---

### E005: "Repeated keys in attribute set"

**Example**:
```nix
# File A: modules/services/syncthing.nix
flake.modules.nixos.syncthing = {
  services.syncthing.enable = true;
};

# File B: modules/hosts/host1.nix
flake.modules.nixos.syncthing = {
  services.syncthing.settings.devices.host1 = { ... };
};
```

**Resolution**: **This is correct!** - Collector pattern

**Why**: Multiple files intentionally define same aspect name. Flake-parts merges them automatically.

**Do NOT fix** - This is proper dendritic collector pattern usage.

## Deadnix Errors

### D001: "Unused argument 'inputs'"

**Example**:
```nix
{ inputs, config, lib, ... }:
{
  # inputs not used in body
}
```

**Resolution**:
- **In `modules/flake-parts/`**: KEEP - Flake-parts module signature
- **In feature modules**: Safe to remove if truly unused
- **Alternative**: Prefix with `_`: `{ _inputs, ... }`

---

### D002: "Unused argument 'config'"

**Example**:
```nix
_: {
  flake.modules.nixos.simple = { config, lib, pkgs, ... }: {
    # config not used
  };
}
```

**Resolution**:
- If module doesn't reference other modules or flake metadata: Safe to remove
- If module might need it later: Use `_config` prefix
- Common in simple modules that just install packages

---

### D003: "Unused binding in let"

**Example**:
```nix
let
  cfg = config.services.myapp;
  unused = "something";
in {
  # unused not referenced
}
```

**Resolution**: Safe to auto-fix

**Fix**: Remove unused binding

## Flake Check Errors

### F001: "infinite recursion detected"

**Symptom**: `nix flake check` fails with recursion error

**Likely cause**: Conditional imports

**Example**:
```nix
imports = lib.mkIf someCondition [
  inputs.self.modules.nixos.someModule
];
```

**Why this fails**: 
- Nix evaluates imports to determine available options
- Condition may depend on options from imported module
- Creates circular dependency

**Fix**: Move condition to config block
```nix
imports = [
  inputs.self.modules.nixos.someModule
];
config = lib.mkIf someCondition {
  # conditional content
};
```

---

### F002: "attribute 'X' already defined"

**Symptom**: Duplicate definition error

**Likely cause**: Collector pattern conflict without merge strategy

**Example**:
```nix
# Module A
flake.modules.nixos.myapp = {
  services.myapp.port = 8080;  # Hard-coded
};

# Module B
flake.modules.nixos.myapp = {
  services.myapp.port = 9090;  # Conflict!
};
```

**Fix**: Use `lib.mkDefault` in base module
```nix
# Base module
services.myapp.port = lib.mkDefault 8080;

# Override in host (not collector)
services.myapp.port = 9090;
```

---

### F003: "attribute 'X' missing" or "option does not exist"

**Symptom**: Reference to undefined option

**Likely cause**: Cross-class import (nixos → darwin)

**Example**:
```nix
flake.modules.darwin.myFeature = {
  imports = [ config.flake.modules.nixos.otherFeature ];
  # Error: services.* doesn't exist in Darwin
};
```

**Fix**: Extract shared code to generic class
```nix
# Shared code
flake.modules.generic.sharedCode = { ... };

# Import generic into both
flake.modules.nixos.myFeature = {
  imports = [ config.flake.modules.generic.sharedCode ];
};
flake.modules.darwin.myFeature = {
  imports = [ config.flake.modules.generic.sharedCode ];
};
```

---

### F004: "value is a set while a list was expected"

**Symptom**: Type error in imports or other list fields

**Likely cause**: Using `//` instead of `lib.mkMerge`

**Example**:
```nix
# ❌ WRONG
config = baseConfig // extraConfig;
# If baseConfig.imports = [a] and extraConfig.imports = [b]
# Result: extraConfig.imports overwrites baseConfig.imports
```

**Fix**: Use `lib.mkMerge`
```nix
# ✅ CORRECT
config = lib.mkMerge [
  baseConfig
  extraConfig
];
```

---

### F005: "value is a function while a set was expected"

**Symptom**: Type error, got function instead of attrset

**Likely cause**: Malformed flake-parts module

**Example**:
```nix
# ❌ WRONG - Missing function wrapper
flake.modules.nixos.broken = {
  services.myapp.enable = true;
};
```

**Fix**: Wrap in function
```nix
# ✅ CORRECT
flake.modules.nixos.fixed = { config, lib, pkgs, ... }: {
  services.myapp.enable = true;
};
```

## Nixpkgs-fmt Warnings

### N001: Inconsistent formatting

**Resolution**: Always safe to auto-fix

**Fix**: Run `nix run .#fmt`

**Note**: Pre-commit hook handles this automatically

## Summary Table

| Error | Safe to Auto-Fix? | Notes |
|-------|-------------------|-------|
| Empty let | ✅ Yes | Everywhere |
| Legacy syntax | ⚠️ Review | Check loaders |
| Unused binding | ✅ Yes | If truly unused |
| Unused argument | ⚠️ Review | Keep in loaders |
| Manual inherit | ⚠️ Review | Keep in loaders |
| mkEnableOption | ❌ No | Dendritic conflict |
| Repeated keys | ❌ No | Collector pattern |
| Formatting | ✅ Yes | Always safe |
| Infinite recursion | ❌ No | Needs fix |
| Duplicate attr | ❌ No | Needs merge strategy |
| Missing option | ❌ No | Needs architecture fix |

**General Rule**: When in doubt, ask before fixing. Dendritic pattern has specific requirements that generic linters don't understand.
