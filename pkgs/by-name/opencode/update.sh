#!/usr/bin/env nix-shell
#! nix-shell -i bash -p nix curl jq

# Update opencode to the latest dev branch commit

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_NIX="$SCRIPT_DIR/package.nix"
HASHES_JSON="$SCRIPT_DIR/hashes.json"

echo "Fetching latest dev branch commit..."
LATEST_COMMIT=$(curl -s "https://api.github.com/repos/sst/opencode/commits/dev" | jq -r '.sha')
echo "Latest commit: $LATEST_COMMIT"

# Check if already at this commit
CURRENT_REV=$(grep -oP 'rev = "\K[^"]+' "$PACKAGE_NIX" || echo "")
if [ "$CURRENT_REV" = "$LATEST_COMMIT" ]; then
    echo "Already at latest commit!"
    exit 0
fi

echo "Updating from $CURRENT_REV to $LATEST_COMMIT..."

# Prefetch the new source
echo "Prefetching source..."
NEW_HASH=$(nix-prefetch-url --unpack "https://github.com/sst/opencode/archive/${LATEST_COMMIT}.tar.gz" 2>/dev/null)
NEW_HASH_SRI=$(nix hash convert --hash-algo sha256 --to sri "$NEW_HASH")

# Update package.nix with new rev and hash
sed -i "s|rev = \".*\";|rev = \"$LATEST_COMMIT\";|" "$PACKAGE_NIX"
sed -i "s|hash = \"sha256-.*\";|hash = \"$NEW_HASH_SRI\";|" "$PACKAGE_NIX"

echo "Updated package.nix"
echo "  rev: $LATEST_COMMIT"
echo "  hash: $NEW_HASH_SRI"

# Now we need to update node_modules hashes
echo ""
echo "Now update node_modules hashes by running:"
echo "  nix build .#opencode 2>&1 | grep 'got:' "
echo ""
echo "Then update hashes.json with the correct hashes for each platform."
echo "You can use: nix run nixpkgs#nix-update -- opencode --subpackage node_modules"
