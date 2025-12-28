#!/usr/bin/env bash
# Update GitHub avatar hash in meta.nix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIXOS_DIR="$(dirname "$SCRIPT_DIR")"
META_FILE="$NIXOS_DIR/modules/flake-parts/meta.nix"

# Get GitHub username from meta.nix
GITHUB_USER=$(grep 'username = "' "$META_FILE" | grep -A 5 'github = {' | tail -1 | sed 's/.*username = "\(.*\)";/\1/')

echo "Fetching avatar for GitHub user: $GITHUB_USER"

# Fetch the new hash
NEW_HASH=$(nix-prefetch-url "https://github.com/$GITHUB_USER.png" 2>/dev/null)

echo "New SHA256 hash: $NEW_HASH"

# Update the hash in meta.nix
sed -i "s/sha256 = \".*\";  *# To update:/sha256 = \"$NEW_HASH\"; # To update:/" "$META_FILE"

echo "✓ Updated avatar hash in $META_FILE"
echo "Run 'sudo nixos-rebuild switch' to apply changes"
