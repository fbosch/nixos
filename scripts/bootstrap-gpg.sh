#!/usr/bin/env bash
# Bootstrap GPG key from Bitwarden for SOPS secrets decryption
# Usage: ./scripts/bootstrap-gpg.sh

set -e

GPG_KEY_ID="fbb.privacy+gpg@protonmail.com"
GPG_FINGERPRINT="5E0FEC74518ED5FEAA5EA33E5C49A562D850322A"

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
if bw get notes "GPG Key" | gpg --import 2>&1; then
    echo "GPG key imported successfully!"
else
    echo "Error: Failed to import GPG key from Bitwarden."
    echo "Make sure you have a secure note named 'GPG Key' in your vault."
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
echo "You can now rebuild your system with secrets:"
echo "  sudo nixos-rebuild switch --flake .#hostname"
