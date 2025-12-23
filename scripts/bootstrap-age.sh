#!/usr/bin/env bash
# Bootstrap age key for a new machine
# 
# This script helps configure SOPS age keys for a new machine.
# It works with auto-generated keys (via sops.age.generateKey = true)
# or can be used to set up keys before the first build.
#
# Usage: ./scripts/bootstrap-age.sh
#
# Workflow:
# 1. Build the system (auto-generates key if missing)
# 2. Run this script to add the key to .sops.yaml
# 3. Re-encrypt secrets
# 4. Rebuild the system
#
# Alternatively, run this script BEFORE first build to set up
# a specific key.

set -e

echo "=== NixOS Age Key Bootstrap ==="
echo

# Detect hostname
HOSTNAME=$(hostname)
echo "Detected hostname: $HOSTNAME"
echo

# Check if sops is installed
if ! command -v sops &> /dev/null; then
    echo "Error: sops not found. Install it first:"
    echo "  nix-shell -p sops age"
    exit 1
fi

# Check if GPG key is available for decryption
if ! gpg --list-secret-keys 5E0FEC74518ED5FEAA5EA33E5C49A562D850322A &> /dev/null; then
    echo "Warning: GPG key not found in keyring."
    echo "You should run bootstrap-gpg.sh first if you need to edit secrets manually."
    echo
fi

# Check if age key already exists
if [ -f /var/lib/sops-nix/key.txt ] && [ -s /var/lib/sops-nix/key.txt ]; then
    echo "Age key already exists at /var/lib/sops-nix/key.txt"
    echo
    AGE_PUBLIC_KEY=$(sudo age-keygen -y /var/lib/sops-nix/key.txt 2>/dev/null || true)
    if [ -n "$AGE_PUBLIC_KEY" ]; then
        echo "Public key: $AGE_PUBLIC_KEY"
        echo
    fi
else
    echo "No age key found. The system will auto-generate one on first build."
    echo "Run 'sudo nixos-rebuild switch' first, then run this script again."
    exit 1
fi

# Extract public key
AGE_PUBLIC_KEY=$(sudo age-keygen -y /var/lib/sops-nix/key.txt)
echo "Age public key: $AGE_PUBLIC_KEY"
echo

# Backup age key to secrets directory
BACKUP_KEY_FILE="secrets/${HOSTNAME}-age-key.txt"
if [ ! -f "$BACKUP_KEY_FILE" ]; then
    echo "Creating backup at $BACKUP_KEY_FILE (gitignored)..."
    sudo cp /var/lib/sops-nix/key.txt "$BACKUP_KEY_FILE"
    sudo chown $USER:users "$BACKUP_KEY_FILE"
    chmod 600 "$BACKUP_KEY_FILE"
    echo "Backup created!"
    echo
fi

# Check if .sops.yaml exists
if [ ! -f .sops.yaml ]; then
    echo "Error: .sops.yaml not found in current directory"
    echo "Run this script from your NixOS configuration directory"
    exit 1
fi

# Check if this hostname key already exists in .sops.yaml
if grep -q "&${HOSTNAME}" .sops.yaml; then
    echo "Age key for '$HOSTNAME' already exists in .sops.yaml"
    echo
    read -p "Do you want to update it with the current key? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing .sops.yaml entry. Exiting."
        exit 0
    fi
    # Remove old key reference
    sed -i "/&${HOSTNAME}/d" .sops.yaml
    # Remove old age reference in creation_rules
    sed -i "/\*${HOSTNAME}/d" .sops.yaml
fi

# Add new age key to .sops.yaml
echo "Adding age public key to .sops.yaml..."

# Find the line number where keys are defined
KEYS_LINE=$(grep -n "^keys:" .sops.yaml | cut -d: -f1)

# Insert new key after the keys: line
sed -i "${KEYS_LINE}a\\  - &${HOSTNAME} ${AGE_PUBLIC_KEY}" .sops.yaml

# Add to creation_rules age section
if grep -q "age:" .sops.yaml; then
    # Add to existing age list
    AGE_SECTION_LINE=$(grep -n "^\s*age:" .sops.yaml | tail -1 | cut -d: -f1)
    sed -i "${AGE_SECTION_LINE}a\\          - *${HOSTNAME}" .sops.yaml
else
    echo "Error: No 'age:' section found in .sops.yaml creation_rules"
    echo "Please manually add the age key reference to your creation_rules"
    exit 1
fi

echo "Updated .sops.yaml successfully!"
echo

# Re-encrypt secrets
echo "Re-encrypting secrets/secrets.yaml with new key..."
if [ -f secrets/secrets.yaml ]; then
    echo "y" | sops updatekeys secrets/secrets.yaml
    echo "Secrets re-encrypted successfully!"
else
    echo "Warning: secrets/secrets.yaml not found"
fi
echo

echo "=== Bootstrap Complete ==="
echo
echo "Age key for '$HOSTNAME' has been:"
echo "  ✓ Found at /var/lib/sops-nix/key.txt"
echo "  ✓ Backed up to $BACKUP_KEY_FILE"
echo "  ✓ Added to .sops.yaml"
echo "  ✓ Used to re-encrypt secrets"
echo
echo "Next steps:"
echo "1. Review the changes to .sops.yaml:"
echo "   git diff .sops.yaml"
echo "2. Commit the updated .sops.yaml (private keys are gitignored):"
echo "   git add .sops.yaml && git commit -m 'Add age key for $HOSTNAME'"
echo "3. Rebuild your system to activate secrets:"
echo "   sudo nixos-rebuild switch --flake .#$HOSTNAME"
