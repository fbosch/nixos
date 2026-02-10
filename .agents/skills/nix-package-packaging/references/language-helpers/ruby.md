# Ruby Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers
- https://raw.githubusercontent.com/manveru/bundix/master/README.md

## Native Builder First

- Prefer nixpkgs Ruby packaging paths (`bundlerApp`, `bundlerEnv`, `ruby.withPackages`) before external generation.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| Typical Bundler-managed app in nixpkgs | `bundlerApp` / `bundlerEnv` | none |
| Need to generate or refresh `gemset.nix` from Bundler metadata | keep bundlerEnv workflow | `bundix` |

## Helpers (Catalog)

- `bundix` - Generate Nix expressions (`gemset.nix`) for Bundler-managed Ruby apps. Upstream: https://github.com/manveru/bundix

## Practical Guidance

- Use `bundix` primarily as a generator feeding native Ruby packaging workflows.
- Re-run gemset generation when lockfile changes.
- Keep generated gemset diffs reviewable and deterministic.

## Example Implementation

```bash
# Generate gemset.nix from Gemfile.lock metadata.
bundix -l
```

```nix
{ pkgs }:
let
  gems = pkgs.bundlerEnv {
    name = "my-ruby-app";
    ruby = pkgs.ruby;
    gemdir = ./.;
  };
in
pkgs.stdenv.mkDerivation {
  pname = "my-ruby-app";
  version = "1.0.0";
  src = ./.;
  buildInputs = [ gems pkgs.ruby ];
  installPhase = ''mkdir -p $out && cp -r $src/* $out/'';
}
```
