#!/usr/bin/env bash
# Bootstrap GPG key from an encrypted secret gist
# Usage: ./scripts/bootstrap/bootstrap-gpg.sh [gist-id]
# If no gist ID is provided, resolves it by searching your gists for the
# expected filename (requires gh auth).

set -euo pipefail

gpg_key_id="fbb.privacy+gpg@protonmail.com"
gpg_gist_filename="gpg-private.asc.gpg"
github_device_url="https://github.com/login/device?skip_account_picker=true"

resolve_gist_ids() {
  gh gist list --limit 100 2>/dev/null | awk -F'\t' -v name="$gpg_gist_filename" 'index($3, name) || index($2, name) { print $1 }'
}

render_github_device_qr() {
  if ! qrencode \
    --type=ANSIUTF8 \
    --level=M \
    --margin=4 \
    --output=- \
    -- "$github_device_url"; then
    printf 'QR rendering failed; open the URL above manually.\n' >&2
  fi
}

show_github_device_qr() {
  if command -v qrencode >/dev/null 2>&1; then
    render_github_device_qr
  fi
}

authenticate_github_cli() {
  if gh auth status >/dev/null 2>&1; then
    printf "GitHub CLI already authenticated.\n"
    return
  fi

  printf "Authenticating GitHub CLI (device flow).\n"
  printf "Use the printed code on another device (phone/laptop).\n"
  printf "Open: %s\n" "$github_device_url"
  show_github_device_qr
  printf '\n' | GH_BROWSER=true gh auth login --web --scopes gist
}

preset_gpg_passphrase_for_sops() {
  local gpg_key_passphrase="$1"
  local key_listing
  local keygrip
  local preset_binary
  local preset_failed="false"
  local -a encryption_keygrips

  if ! key_listing="$(gpg --batch --with-colons --with-keygrip --list-secret-keys "$gpg_key_id")"; then
    printf "Error: Failed to inspect the imported GPG key.\n"
    return 1
  fi

  mapfile -t encryption_keygrips < <(
    awk -F: '
      $1 == "sec" || $1 == "ssb" { encrypt = index($12, "e") > 0; next }
      $1 == "grp" && encrypt { print $10 }
    ' <<<"$key_listing"
  )
  if [ "${#encryption_keygrips[@]}" -eq 0 ]; then
    printf "Error: Imported GPG key has no encryption keygrip.\n"
    return 1
  fi

  preset_binary="$(gpgconf --list-dirs libexecdir)/gpg-preset-passphrase"
  if [ ! -x "$preset_binary" ]; then
    printf "Error: gpg-preset-passphrase is unavailable.\n"
    return 1
  fi

  for keygrip in "${encryption_keygrips[@]}"; do
    if ! printf "%s" "$gpg_key_passphrase" | "$preset_binary" --preset "$keygrip"; then
      preset_failed="true"
      break
    fi
  done
  unset gpg_key_passphrase

  if [ "$preset_failed" = "false" ] &&
    printf "SOPS GPG passphrase check" |
    gpg --batch --yes --quiet --trust-model always --recipient "$gpg_key_id" --encrypt 2>/dev/null |
      gpg --batch --yes --quiet --pinentry-mode error --decrypt >/dev/null 2>&1; then
    printf "GPG key passphrase cached for SOPS.\n"
    return
  fi

  for keygrip in "${encryption_keygrips[@]}"; do
    "$preset_binary" --forget "$keygrip" >/dev/null 2>&1 || true
  done
  printf "Error: Failed to unlock the imported GPG key.\n"
  printf "Check the private-key passphrase (not the backup archive passphrase).\n"
  return 1
}

cache_gpg_passphrase_for_sops() {
  if [ "${BOOTSTRAP_GPG_CACHE_FOR_SOPS:-false}" != "true" ]; then
    return
  fi

  local gpg_key_passphrase

  if [ ! -r /dev/tty ]; then
    printf "Error: No TTY available for GPG key passphrase prompt.\n"
    return 1
  fi
  if IFS= read -r -p "Enter passphrase for imported GPG key (required by SOPS): " gpg_key_passphrase </dev/tty; then
    printf "\n" >/dev/tty
  else
    printf "\nError: Failed to read GPG key passphrase from TTY.\n"
    return 1
  fi

  if preset_gpg_passphrase_for_sops "$gpg_key_passphrase"; then
    unset gpg_key_passphrase
    return
  fi
  unset gpg_key_passphrase
  return 1
}

if [ "${BOOTSTRAP_GPG_LIB_ONLY:-false}" = "true" ]; then
  if [ "${BASH_SOURCE[0]}" != "$0" ]; then
    return 0
  fi
  exit 0
fi

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
  if [[ $reply =~ ^[Yy]$ ]]; then
    :
  else
    printf "Skipping GPG import. Exiting.\n"
    exit 0
  fi
fi

authenticate_github_cli

if [ -n "${1:-}" ]; then
  gist_id="$1"
elif [ -n "${GPG_KEY_GIST_ID:-}" ]; then
  gist_id="$GPG_KEY_GIST_ID"
else
  printf "Resolving gist ID by filename (%s)...\n" "$gpg_gist_filename"
  mapfile -t gist_ids < <(resolve_gist_ids)
  if [ "${#gist_ids[@]}" -eq 0 ]; then
    printf "Error: Could not find a gist containing '%s'.\n" "$gpg_gist_filename"
    printf "Pass the gist ID explicitly: %s <gist-id>\n" "$0"
    exit 1
  fi
  if [ "${#gist_ids[@]}" -gt 1 ]; then
    printf "Error: Found multiple gists containing '%s'.\n" "$gpg_gist_filename"
    printf "Pass the desired gist ID explicitly: %s <gist-id>\n" "$0"
    exit 1
  fi
  gist_id="${gist_ids[0]}"
  printf "Found gist: %s\n" "$gist_id"
fi

tmp_encrypted="$(mktemp)"
tmp_decrypted="$(mktemp)"
tmp_error="$(mktemp)"
cleanup() {
  rm -f "$tmp_encrypted"
  rm -f "$tmp_decrypted"
  rm -f "$tmp_error"
}
trap cleanup EXIT

printf "Downloading encrypted key from gist %s...\n" "$gist_id"
download_ok="false"
scope_refreshed="false"
download_attempts=6
download_sleep_seconds=3

for attempt in $(seq 1 "$download_attempts"); do
  if gh gist view "$gist_id" --raw >"$tmp_encrypted" 2>"$tmp_error"; then
    download_ok="true"
    break
  fi

  if grep -Eiq "scope|forbidden|401|403" "$tmp_error" && [ "$scope_refreshed" = "false" ]; then
    printf "Refreshing GitHub auth scopes for gist access.\n"
    gh auth refresh -h github.com -s gist
    scope_refreshed="true"
    continue
  fi

  if [ "$attempt" -lt "$download_attempts" ]; then
    printf "Download failed (attempt %s/%s). Retrying in %ss...\n" "$attempt" "$download_attempts" "$download_sleep_seconds"
    sleep "$download_sleep_seconds"
  fi
done

if [ "$download_ok" = "false" ]; then
  printf "Error: Failed to download gist after %s attempts.\n" "$download_attempts"
  printf "Last error:\n"
  cat "$tmp_error"
  exit 1
fi

printf "Decrypting and importing GPG key...\n"
if [ -r /dev/tty ]; then
  if IFS= read -r -p "Enter passphrase for encrypted GPG backup: " gpg_backup_passphrase </dev/tty; then
    printf "\n" >/dev/tty
  else
    printf "\nError: Failed to read passphrase from TTY.\n"
    exit 1
  fi
else
  printf "Error: No TTY available for passphrase prompt.\n"
  exit 1
fi

if printf "%s" "$gpg_backup_passphrase" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --decrypt --output "$tmp_decrypted" "$tmp_encrypted"; then
  :
else
  printf "Error: Failed to decrypt key backup from gist.\n"
  printf "Check passphrase and gist content.\n"
  exit 1
fi

if gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --import "$tmp_decrypted" <<<"$gpg_backup_passphrase" 2>&1; then
  printf "GPG key imported successfully.\n"
else
  printf "Error: Failed to decrypt or import GPG key from gist.\n"
  printf "Check passphrase and gist content.\n"
  exit 1
fi
unset gpg_backup_passphrase
cache_gpg_passphrase_for_sops

printf "\nSetting ultimate trust for GPG key...\n"
if printf "trust\n5\ny\nquit\n" | gpg --command-fd 0 --edit-key "$gpg_key_id" >/dev/null 2>&1; then
  printf "GPG key configured with ultimate trust.\n"
else
  printf "Warning: Failed to set trust level automatically.\n"
  printf "Run manually: gpg --edit-key %s\n" "$gpg_key_id"
fi

printf "\n=== Bootstrap Complete ===\n\n"
printf "GPG key is now available for manual secret editing.\n"
