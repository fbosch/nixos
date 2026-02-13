#!/usr/bin/env bash
# Re-encrypt all repository SOPS secret files with current .sops.yaml keys.

set -euo pipefail

if [ ! -f .sops.yaml ]; then
  echo "Error: .sops.yaml not found. Run from repository root." >&2
  exit 1
fi

shopt -s nullglob
secret_files=(secrets/*.yaml)
shopt -u nullglob

if [ ${#secret_files[@]} -eq 0 ]; then
  echo "No secret YAML files found under secrets/."
  exit 0
fi

echo "Updating SOPS keys for ${#secret_files[@]} files..."
for file in "${secret_files[@]}"; do
  echo "  - $file"
  echo "y" | sops updatekeys "$file"
done

echo "Done."
echo "Next: run darwin-rebuild/nixos-rebuild switch to apply."
