#!/usr/bin/env bash
set -euo pipefail

readonly secrets_encryption_key_path="/var/lib/libvirt/secrets/secrets-encryption-key"

umask 0077

dd if=/dev/random status=none bs=32 count=1 |
 systemd-creds encrypt --name=secrets-encryption-key - "$secrets_encryption_key_path"
