#!/usr/bin/env bash
# Bootstrap GPG key from Bitwarden for SOPS secrets decryption
# Usage: ./scripts/bootstrap-gpg.sh

set -e

GPG_KEY_ID="fbb.privacy+gpg@protonmail.com"
GPG_FINGERPRINT="5E0FEC74518ED5FEAA5EA33E5C49A562D850322A"
BW_KEY_NOTE="GPG Private Key"
BW_SERVER_URL="https://vault.corvus-corax.synology.me"

# Ensure Bitwarden CLI uses a writable data directory
export BITWARDENCLI_APPDATA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Bitwarden CLI"
mkdir -p "$BITWARDENCLI_APPDATA_DIR"

# Remove Home Manager managed symlink if it exists (it points to read-only nix store)
if [ -L "$BITWARDENCLI_APPDATA_DIR/data.json" ]; then
    echo "Removing Home Manager managed Bitwarden CLI data.json symlink..."
    rm "$BITWARDENCLI_APPDATA_DIR/data.json"
fi

# Initialize data.json with server URL if it doesn't exist or is empty
if [ ! -f "$BITWARDENCLI_APPDATA_DIR/data.json" ] || [ ! -s "$BITWARDENCLI_APPDATA_DIR/data.json" ]; then
    echo "Initializing Bitwarden CLI with server URL: $BW_SERVER_URL"
    echo "{\"serverUrl\":\"$BW_SERVER_URL\"}" > "$BITWARDENCLI_APPDATA_DIR/data.json"
fi

echo "=== NixOS GPG Bootstrap ==="
echo

# Check if GPG key already exists
if gpg --list-secret-keys "$GPG_KEY_ID" &> /dev/null; then
    echo "GPG key already exists on this system!"
    echo
    gpg --list-secret-keys --keyid-format=long "$GPG_KEY_ID"
    echo
    read -p "Do you want to re-import it anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Skipping GPG import. Exiting."
        exit 0
    fi
fi

# Check if Bitwarden CLI is installed
if ! command -v bw &> /dev/null; then
    echo "Error: Bitwarden CLI not found. Install it first:"
    echo "  nix-shell -p bitwarden-cli"
    exit 1
fi

# Check if already logged in
if ! bw login --check &> /dev/null; then
    echo "Logging in to Bitwarden..."
    bw login
    echo
fi

# Unlock vault
echo "Unlocking Bitwarden vault..."
if [ -z "$BW_SESSION" ]; then
    export BW_SESSION=$(bw unlock --raw)
fi
echo "Vault unlocked!"
echo

# Import GPG key
echo "Importing GPG key from Bitwarden..."
if bw get notes "$BW_KEY_NOTE" | gpg --import 2>&1; then
    echo "GPG key imported successfully!"
else
    echo "Error: Failed to import GPG key from Bitwarden."
    echo "Make sure you have a secure note named '$BW_KEY_NOTE' in your vault."
    exit 1
fi
echo

# Set trust level
echo "Setting ultimate trust for GPG key..."
if echo -e "trust\n5\ny\nquit" | gpg --command-fd 0 --edit-key "$GPG_KEY_ID" &> /dev/null; then
    echo "GPG key configured with ultimate trust!"
else
    echo "Warning: Failed to set trust level. You may need to trust the key manually:"
    echo "  gpg --edit-key $GPG_KEY_ID"
    echo "  (then type: trust, 5, quit)"
fi
echo

echo "=== Bootstrap Complete ==="
echo
echo "GPG key is now available in your user keyring for manual secret editing."
echo "You can now edit secrets files under secrets/ (for example: sops secrets/common.yaml)"
echo
echo "Next steps:"
echo "1. Build the system (this will auto-generate an age key):"
echo "   sudo nixos-rebuild switch --flake .#\$(hostname)"
echo
echo "2. Add the age key to .sops.yaml and re-encrypt secrets:"
echo "   ./scripts/bootstrap-age.sh"
echo
echo "3. Rebuild to activate secrets:"
echo "   sudo nixos-rebuild switch --flake .#\$(hostname)"
