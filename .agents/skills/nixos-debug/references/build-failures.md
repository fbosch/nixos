# Build Failure Patterns

## Infinite Recursion Errors

### Pattern: "infinite recursion encountered"

**Cause**: Circular dependencies in module system

**Example error**:
```
error: infinite recursion encountered
  at /nix/store/.../modules/desktop/hyprland.nix:12:5
```

**Common violations**:
```nix
# ❌ Conditional imports cause recursion
imports = lib.mkIf someCondition [ someModule ];
imports = lib.optional cfg.enable someModule;

# ❌ Module references itself
imports = [ ./. ];

# ❌ Circular dependency chain
# module-a imports module-b
# module-b imports module-a
```

**Fix**: Remove circular references and conditional imports
```nix
# ✅ Correct - unconditional imports
imports = [ someModule ];

# ✅ Use conditions in config, not imports
config = lib.mkIf someCondition { 
  services.myapp.enable = true;
};
```

**Diagnosis steps**:
1. Find file mentioned in stack trace
2. Check imports chain for circular dependencies
3. Search for conditional imports: `rg "imports.*mkIf|imports.*optional"`
4. Verify module doesn't import itself directly or indirectly
5. Load `dendritic-pattern` skill if using that architecture pattern

---

## Attribute Already Defined

### Pattern: "attribute 'X' already defined at Y"

**Cause 1**: Duplicate definitions without priority/merge

**Example error**:
```
error: attribute 'services.nginx.port' already defined at
  /path/to/modules/services/nginx.nix:15
  previously defined at
  /path/to/modules/hosts/desktop.nix:42
```

**Fix**: Use `lib.mkDefault` for overridable defaults:
```nix
# Base module (modules/services/nginx.nix)
services.nginx.port = lib.mkDefault 80;  # ✅ Can be overridden

# Override in specific config
services.nginx.port = 8080;  # ✅ Takes precedence
```

**Cause 2**: Using `//` instead of `lib.mkMerge`

**Example**:
```nix
# ❌ Wrong - shallow merge loses nested config
config = base // override;

# ✅ Correct - deep merge preserves all config
config = lib.mkMerge [ base override ];
```

**Diagnosis steps**:
1. Identify which attribute is duplicated from error message
2. Check if one should override the other (use `lib.mkDefault` in base)
3. Search for shallow merge: `rg "= .* // " modules/`
4. Verify both definitions are needed (not accidental duplicate)
5. Check if multiple files intentionally define same value (needs merge strategy)

---

## Attribute Missing / Option Does Not Exist

### Pattern: "attribute 'X' missing" or "The option 'X' does not exist"

**Cause**: Option undefined in current context

**Example error**:
```
error: The option 'services.xserver' does not exist
  defined in /path/to/modules/desktop/hyprland.nix
```

**Common causes**:
1. Platform mismatch (NixOS option in Darwin config, or vice versa)
2. Typo in option name
3. Module providing option not imported
4. Option only exists in different NixOS version

**Fix for platform mismatch**: Separate platform-specific config
```nix
# ❌ Wrong - NixOS option in Darwin context
services.xserver.enable = true;  # Only exists on NixOS

# ✅ Correct - platform-specific config
# In NixOS config:
services.xserver.enable = true;

# In Darwin config:
# Use Darwin-equivalent options instead
```

**Diagnosis steps**:
1. Check which platform/system is building
2. Search for option in nixpkgs: `nix-instantiate --eval --expr '(import <nixpkgs/nixos> {}).options.services.xserver' `
3. Verify module providing option is imported
4. Check NixOS option search: https://search.nixos.org/options
5. For multi-platform flakes, load `dendritic-pattern` skill for class separation guidance

---

## Evaluation Error: Expecting Lambda

### Pattern: "value is X while a function was expected" or "cannot coerce X to a function"

**Cause**: Incorrect module structure

**Example error**:
```
error: value is an attribute set while a function was expected
  at /path/to/modules/myfeature.nix:1:1
```

**Common mistakes**:
```nix
# ❌ Wrong - direct attribute set instead of function
{
  services.myapp.enable = true;
}

# ✅ Correct - module is a function
{ config, lib, pkgs, ... }:
{
  services.myapp.enable = true;
}
```

**Diagnosis steps**:
1. Open file mentioned in error
2. Verify module starts with function signature: `{ config, lib, ... }:`
3. Check module structure matches your flake's expected format
4. Validate syntax: `nix-instantiate --parse modules/myfeature.nix`

---

## Flake Check Failures

### Pattern: "nix flake check" fails but rebuild succeeds

**Common causes**:
- Syntax errors in non-imported modules (prefixed with `_`)
- Lint errors (statix/deadnix)
- Broken perSystem outputs (packages, devShells)
- Missing dependencies in checks

**Diagnosis workflow**:
```bash
# 1. Run flake check with verbose output
nix flake check --show-trace

# 2. If evaluation errors, check syntax
nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel --show-trace

# 3. If lint errors, run lint check
nix run .#lint

# 4. If perSystem errors, check package definitions
nix eval .#packages.x86_64-linux --apply builtins.attrNames
```

---

## Hash Mismatch Errors

### Pattern: "hash mismatch in fixed-output derivation"

**Cause**: Cached derivation has wrong hash (upstream changed)

**Example error**:
```
error: hash mismatch in fixed-output derivation '/nix/store/...-source':
  specified: sha256-abc...
  got:       sha256-xyz...
```

**Fix**: Update hash in source definition:
```nix
# Update fetchFromGitHub, fetchurl, etc. with new hash
src = pkgs.fetchFromGitHub {
  owner = "owner";
  repo = "repo";
  rev = "v1.2.3";
  hash = "sha256-xyz...";  # Use hash from error message
};
```

**Quick hash update**:
```bash
# Set hash to empty string or fake hash
hash = "";  # or sha256-AAAA...

# Build to get correct hash in error
nix build .#package

# Copy hash from error into source
```

---

## Module Recursion (Self-Reference)

### Pattern: "infinite recursion" in module evaluation

**Cause**: Module references itself in imports

**Example**:
```nix
# ❌ Wrong - module imports itself
flake.modules.nixos.myfeature = {
  imports = [ config.flake.modules.nixos.myfeature ];
};
```

**Fix**: Remove self-reference, use inheritance pattern:
```nix
# Create base module
flake.modules.nixos.myfeature-base = { ... };

# Extended module imports base
flake.modules.nixos.myfeature = {
  imports = [ config.flake.modules.nixos.myfeature-base ];
};
```

---

## Unknown Option

### Pattern: "The option 'X' defined in 'Y' does not exist"

**Cause 1**: Typo in option name
**Cause 2**: Module not imported providing the option
**Cause 3**: Option only exists in newer/older NixOS version

**Diagnosis**:
```bash
# Search available options
nix-instantiate --eval --expr \
  'builtins.attrNames (import <nixpkgs/nixos> {}).options'

# Check if module is imported
nix eval .#nixosConfigurations.<hostname>.config.imports

# Check NixOS version
nixos-version
```

**Fix**: Verify spelling, import required module, or check version compatibility
