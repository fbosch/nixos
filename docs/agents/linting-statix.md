# Statix Linting Rules

## W20: Avoid repeated keys in attribute sets

**Problem**: Using the same attribute key multiple times in one scope.

```nix
# ❌ Wrong - repeated 'inputs' key
winapps = {
  url = "...";
  inputs.nixpkgs.follows = "nixpkgs";
  inputs.flake-utils.follows = "dedupe_flake-utils";
  inputs.flake-compat.follows = "dedupe_flake-compat";
};

# ✅ Correct - nested under single 'inputs' key
winapps = {
  url = "...";
  inputs = {
    nixpkgs.follows = "nixpkgs";
    flake-utils.follows = "dedupe_flake-utils";
    flake-compat.follows = "dedupe_flake-compat";
  };
};
```

## Other common rules

- Avoid empty let blocks; remove `let` if no bindings are defined.
- Avoid legacy attribute syntax; use `inherit` instead of repeating names.
- Prefer `lib.mkIf` over nested if expressions.
- Use `mkEnableOption` for boolean options.
- Use `stdenv.hostPlatform.system` instead of `system` (deprecated).

```nix
# ❌ Wrong - deprecated 'system' parameter
{ pkgs, system, ... }:
let
  package = inputs.self.packages.${system}.foo;
in { }

# ✅ Correct - use stdenv.hostPlatform.system
{ pkgs, ... }:
let
  package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.foo;
in { }
```
