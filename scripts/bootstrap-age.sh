#!/usr/bin/env bash
# Bootstrap age key for a new machine
# This script:
# 1. Detects the current hostname
# 2. Generates a new age key for this machine
# 3. Installs it to /var/lib/sops-nix/key.txt
# 4. Updates .sops.yaml with the new public key
# 5. Re-encrypts secrets with the new key
#
# Usage: ./scripts/bootstrap-age.sh

set -e

echo "=== NixOS Age Key Bootstrap ==="
echo

# Detect hostname
HOSTNAME=$(hostname)
echo "Detected hostname: $HOSTNAME"
echo

# Check if age is installed
if ! command -v age-keygen &> /dev/null; then
    echo "Error: age not found. Install it first:"
    echo "  nix-shell -p age"
    exit 1
fi

# Check if sops is installed
if ! command -v sops &> /dev/null; then
    echo "Error: sops not found. Install it first:"
    echo "  nix-shell -p sops"
    exit 1
fi

# Check if GPG key is available for decryption
if ! gpg --list-secret-keys 5E0FEC74518ED5FEAA5EA33E5C49A562D850322A &> /dev/null; then
    echo "Error: GPG key not found in keyring."
    echo "Please run bootstrap-gpg.sh first to import your GPG key."
    exit 1
fi

# Check if age key already exists
if [ -f /var/lib/sops-nix/key.txt ]; then
    echo "Age key already exists at /var/lib/sops-nix/key.txt"
    echo
    sudo age-keygen -y /var/lib/sops-nix/key.txt
    echo
    read -p "Do you want to regenerate it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Keeping existing age key. Exiting."
        exit 0
    fi
fi

# Generate age key
echo "Generating age key for $HOSTNAME..."
AGE_KEY_FILE="/tmp/age-key-$HOSTNAME.txt"
age-keygen -o "$AGE_KEY_FILE" 2>&1

# Extract public key
AGE_PUBLIC_KEY=$(age-keygen -y "$AGE_KEY_FILE")
echo "Generated age public key: $AGE_PUBLIC_KEY"
echo

# Install to system location
echo "Installing age key to /var/lib/sops-nix/key.txt..."
sudo mkdir -p /var/lib/sops-nix
sudo mv "$AGE_KEY_FILE" /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
echo "Age key installed successfully!"
echo

# Backup age key to secrets directory
BACKUP_KEY_FILE="secrets/${HOSTNAME}-age-key.txt"
echo "Creating backup at $BACKUP_KEY_FILE (gitignored)..."
sudo cp /var/lib/sops-nix/key.txt "$BACKUP_KEY_FILE"
sudo chown $USER:$USER "$BACKUP_KEY_FILE"
chmod 600 "$BACKUP_KEY_FILE"
echo "Backup created!"
echo

# Check if .sops.yaml exists
if [ ! -f .sops.yaml ]; then
    echo "Error: .sops.yaml not found in current directory"
    exit 1
fi

# Check if this hostname key already exists in .sops.yaml
if grep -q "$HOSTNAME" .sops.yaml; then
    echo "Hostname '$HOSTNAME' already exists in .sops.yaml"
    echo "Updating the public key..."
    # Remove old key reference
    sed -i "/&${HOSTNAME}/d" .sops.yaml
fi

# Add new age key to .sops.yaml
echo "Adding age public key to .sops.yaml..."

# Find the line number where keys are defined
KEYS_LINE=$(grep -n "^keys:" .sops.yaml | cut -d: -f1)

# Insert new key after the keys: line
sed -i "${KEYS_LINE}a\\  - &${HOSTNAME} ${AGE_PUBLIC_KEY}" .sops.yaml

# Check if age key already exists in creation_rules
if grep -q "age:" .sops.yaml; then
    # Add to existing age list
    AGE_SECTION_LINE=$(grep -n "age:" .sops.yaml | tail -1 | cut -d: -f1)
    sed -i "${AGE_SECTION_LINE}a\\          - *${HOSTNAME}" .sops.yaml
else
    echo "Warning: No 'age:' section found in .sops.yaml creation_rules"
    echo "Please manually add the age key reference to your creation_rules"
fi

echo "Updated .sops.yaml successfully!"
echo

# Re-encrypt secrets
echo "Re-encrypting secrets/secrets.yaml with new key..."
if [ -f secrets/secrets.yaml ]; then
    sops updatekeys secrets/secrets.yaml
    echo "Secrets re-encrypted successfully!"
else
    echo "Warning: secrets/secrets.yaml not found"
fi
echo

echo "=== Bootstrap Complete ==="
echo "Age key for '$HOSTNAME' has been:"
echo "  ✓ Generated and installed to /var/lib/sops-nix/key.txt"
echo "  ✓ Backed up to $BACKUP_KEY_FILE"
echo "  ✓ Added to .sops.yaml"
echo "  ✓ Used to re-encrypt secrets"
echo
echo "Next steps:"
echo "1. Review the changes to .sops.yaml"
echo "2. Commit the updated .sops.yaml (but NOT the private key)"
echo "3. Rebuild your system:"
echo "   sudo nixos-rebuild switch --flake .#$HOSTNAME"
