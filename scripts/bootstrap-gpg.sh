#!/usr/bin/env bash
# Bootstrap GPG key from an encrypted secret gist
# Usage: ./scripts/bootstrap-gpg.sh [gist-id]

set -euo pipefail

gpg_key_id="fbb.privacy+gpg@protonmail.com"
default_gist_id="68308e969e326a4c4fa2529fbf211006"
gist_id="${1:-${GPG_KEY_GIST_ID:-$default_gist_id}}"

printf "=== NixOS GPG Bootstrap ===\n\n"

if ! command -v gh >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
  printf "Error: gh and gpg must be available.\n"
  exit 1
fi

if gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
  printf "GPG key already exists on this system.\n\n"
  gpg --list-secret-keys --keyid-format=long "$gpg_key_id"
  printf "\n"
  read -r -p "Do you want to re-import it anyway? (y/N): " reply
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    :
  else
    printf "Skipping GPG import. Exiting.\n"
    exit 0
  fi
fi

if gh auth status >/dev/null 2>&1; then
  printf "GitHub CLI already authenticated.\n"
else
  printf "Authenticating GitHub CLI (device flow).\n"
  printf "Open: https://github.com/login/device?skip_account_picker=true\n"
  gh auth login --web --scopes gist
fi

if gh api "gists/$gist_id" >/dev/null 2>&1; then
  :
else
  printf "Refreshing GitHub auth scopes for gist access.\n"
  gh auth refresh -h github.com -s gist
fi

tmp_encrypted="$(mktemp)"
cleanup() {
  rm -f "$tmp_encrypted"
}
trap cleanup EXIT

printf "Downloading encrypted key from gist %s...\n" "$gist_id"
gh gist view "$gist_id" --raw >"$tmp_encrypted"

printf "Decrypting and importing GPG key...\n"
if gpg --decrypt "$tmp_encrypted" | gpg --import 2>&1; then
  printf "GPG key imported successfully.\n"
else
  printf "Error: Failed to decrypt or import GPG key from gist.\n"
  printf "Check passphrase and gist content.\n"
  exit 1
fi

printf "\nSetting ultimate trust for GPG key...\n"
if printf "trust\n5\ny\nquit\n" | gpg --command-fd 0 --edit-key "$gpg_key_id" >/dev/null 2>&1; then
  printf "GPG key configured with ultimate trust.\n"
else
  printf "Warning: Failed to set trust level automatically.\n"
  printf "Run manually: gpg --edit-key %s\n" "$gpg_key_id"
fi

printf "\n=== Bootstrap Complete ===\n\n"
printf "GPG key is now available for manual secret editing.\n"
