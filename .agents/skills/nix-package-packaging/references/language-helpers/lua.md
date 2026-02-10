# Lua Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native-First Baseline

- Prefer existing nixpkgs Lua packaging conventions first.
- Use generation when LuaRocks dependency translation is the dominant maintenance cost.

## Decision Playbook

| Signal | Action |
|---|---|
| Project dependency model is rockspec-driven and changes often | use `luarocks2nix` |
| Only a small fixed dependency set exists | package directly without helper generation |
| Generated expressions need manual edits every cycle | minimize helper usage to high-churn dependencies only |

## Helper

- `luarocks2nix` - Convert LuaRocks metadata into Nix derivations. Upstream: https://github.com/nix-community/luarocks-nix

## Failure Signatures and Fixes

- Signature: generated dependencies differ from runtime expectations.
  - First fix: re-sync generation from current rockspec/lock source.
  - Second fix: pin versions explicitly in derivation when upstream metadata is ambiguous.
- Signature: helper output imports paths/layout not matching current repo structure.
  - First fix: normalize generated call paths.
  - Second fix: switch to direct packaging for stable modules.

## Abandon Helper When

- Most generated output is patched manually anyway.
- Dependency graph is small enough to maintain by hand.

## Example Implementation

```nix
{ pkgs, ... }:
let
  # Example: generated from LuaRocks metadata.
  luaPackagesGenerated = import ./luarocks-packages-generated.nix { inherit pkgs; };
in
luaPackagesGenerated.my-lua-app
```
