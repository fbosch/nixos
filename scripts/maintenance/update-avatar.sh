#!/usr/bin/env bash
# Update GitHub avatar hash in flake metadata

set -euo pipefail

NIXOS_DIR="$(git rev-parse --show-toplevel)"
META_FILE="$NIXOS_DIR/modules/flake-parts/meta/default.nix"

# Get GitHub username from the github block in meta
GITHUB_USER=$(awk '/github = \{/ {in_github=1; next} in_github && /username = "/ {gsub(/.*username = "|".*/, ""); print; exit}' "$META_FILE")

echo "Fetching avatar for GitHub user: $GITHUB_USER"

# Fetch the new hash
NEW_HASH=$(nix-prefetch-url "https://github.com/$GITHUB_USER.png" 2>/dev/null)

echo "New SHA256 hash: $NEW_HASH"

# Update the avatar hash in meta
sed -i "s|sha256 = \"[0-9a-z]*\";|sha256 = \"$NEW_HASH\";|" "$META_FILE"

echo "✓ Updated avatar hash in $META_FILE"
echo "Run 'sudo nixos-rebuild switch' to apply changes"
