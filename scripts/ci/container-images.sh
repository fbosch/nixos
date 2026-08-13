#!/usr/bin/env bash
set -euo pipefail

nix eval --json '.#nixosConfigurations' --apply 'configurations: builtins.attrNames configurations' |
  jq -r '.[]' |
  while IFS= read -r host; do
    # shellcheck disable=SC2016 # Nix interpolation must remain literal for --apply.
    nix eval --json ".#nixosConfigurations.${host}.config.environment.etc" --apply '
      etc:
      builtins.map
        (name: etc.${name}.text)
        (builtins.filter
          (name: builtins.match "containers/systemd/.*[.]container" name != null)
          (builtins.attrNames etc))
    '
  done |
  jq -r '.[] | split("\n")[] | select(startswith("Image=")) | ltrimstr("Image=")' |
  sort -u
