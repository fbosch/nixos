#!/usr/bin/env bash

set -euo pipefail

expected_fingerprint="5E0FEC74518ED5FEAA5EA33E5C49A562D850322A"
gpg_gist_filename="gpg-private.asc.gpg"
gist_id="${GPG_KEY_GIST_ID:-}"
backup_file=""
check_key_passphrase="true"

usage() {
  cat <<EOF
Usage: $0 [--backup-only] [--file <path> | <gist-id>]

Verify the encrypted GPG backup gist in a throwaway keyring. Checks that the
backup passphrase decrypts it, that it contains the admin key
($expected_fingerprint), and that the key passphrase unlocks that key.

  --backup-only  Skip the key passphrase check
  --file <path>  Verify a local backup file instead of downloading the gist

Passphrases are prompted on a terminal, or read one per line from stdin.
EOF
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    return
  fi

  printf "Error: %s must be available.\n" "$1"
  exit 1
}

ensure_gh_auth() {
  if gh auth status >/dev/null 2>&1; then
    return
  fi

  printf "Authenticating GitHub CLI (device flow).\n"
  printf "Open: https://github.com/login/device?skip_account_picker=true\n"
  gh auth login --web --scopes gist
}

list_matching_gist_ids() {
  gh gist list --limit 100 2>/dev/null | awk -F'\t' -v name="$gpg_gist_filename" '
    index($3, name) || index($2, name) { print $1 }
  '
}

read_secret() {
  local prompt="$1"
  local value=""

  # Prompt silently on a terminal; otherwise read one line per passphrase from stdin.
  if [ -t 0 ]; then
    IFS= read -rs -p "$prompt" value
    printf "\n" >&2
  else
    IFS= read -r value || true
  fi
  printf "%s" "$value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --backup-only)
    check_key_passphrase="false"
    shift
    ;;
  --file)
    if [ -z "${2:-}" ]; then
      printf "Error: --file requires a value.\n"
      exit 1
    fi
    backup_file="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    printf "Error: Unknown argument: %s\n" "$1"
    usage
    exit 1
    ;;
  *)
    gist_id="$1"
    shift
    ;;
  esac
done

printf "=== Verify GPG Backup Gist ===\n\n"

require_command gpg
require_command gpgconf

umask 077
# Keep the decrypted key and throwaway keyring on the runtime tmpfs when available.
work_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/verify-gpg-gist.XXXXXX")"
gnupg_home="$work_dir/gnupg"
encrypted_file="$work_dir/$gpg_gist_filename"
decrypted_file="$work_dir/gpg-private.asc"
mkdir -m 0700 "$gnupg_home"

cleanup() {
  gpgconf --homedir "$gnupg_home" --kill all >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

gpg_tmp() {
  gpg --homedir "$gnupg_home" --batch --quiet "$@"
}

if [ -n "$backup_file" ]; then
  printf "Using local backup: %s\n" "$backup_file"
  cp "$backup_file" "$encrypted_file"
else
  require_command gh
  ensure_gh_auth

  if [ -z "$gist_id" ]; then
    mapfile -t matching_gists < <(list_matching_gist_ids)
    if [ "${#matching_gists[@]}" -ne 1 ]; then
      printf "Error: Expected one gist containing '%s', found %s.\n" "$gpg_gist_filename" "${#matching_gists[@]}"
      printf "Pass the gist ID explicitly: %s <gist-id>\n" "$0"
      exit 1
    fi
    gist_id="${matching_gists[0]}"
  fi

  printf "Downloading gist %s...\n" "$gist_id"
  gh gist view "$gist_id" --raw --filename "$gpg_gist_filename" >"$encrypted_file"
fi

if grep -q -- '-----BEGIN PGP MESSAGE-----' "$encrypted_file"; then
  printf "Format: ASCII-armored\n"
else
  printf "Warning: Backup is not ASCII-armored; gist uploads and downloads may corrupt it.\n"
fi

backup_passphrase="$(read_secret "Backup passphrase: ")"
if printf "%s" "$backup_passphrase" | gpg_tmp \
  --pinentry-mode loopback \
  --passphrase-fd 0 \
  --decrypt \
  --output "$decrypted_file" \
  "$encrypted_file" 2>/dev/null; then
  printf "OK    Backup passphrase decrypts the backup.\n"
else
  printf "FAIL  Backup passphrase did not decrypt the backup.\n"
  exit 1
fi
unset backup_passphrase

if ! gpg_tmp --pinentry-mode error --import "$decrypted_file" 2>/dev/null; then
  printf "FAIL  Decrypted backup is not an importable GPG key.\n"
  exit 1
fi
rm -f "$decrypted_file"

imported_fingerprint="$(gpg_tmp --with-colons --list-secret-keys | awk -F: '$1 == "fpr" { print $10; exit }')"
if [ "$imported_fingerprint" = "$expected_fingerprint" ]; then
  printf "OK    Backup contains secret key %s.\n" "$expected_fingerprint"
else
  printf "FAIL  Expected secret key %s, found '%s'.\n" "$expected_fingerprint" "$imported_fingerprint"
  exit 1
fi

if [ "$check_key_passphrase" = "false" ]; then
  printf "\nSkipped key passphrase check (--backup-only).\n"
  exit 0
fi

probe_file="$work_dir/probe.gpg"
printf "verify-gpg-gist probe" | gpg_tmp \
  --trust-model always \
  --recipient "$expected_fingerprint" \
  --encrypt \
  --output "$probe_file"

key_passphrase="$(read_secret "Key passphrase: ")"
if printf "%s" "$key_passphrase" | gpg_tmp \
  --pinentry-mode loopback \
  --passphrase-fd 0 \
  --decrypt \
  "$probe_file" >/dev/null 2>&1; then
  printf "OK    Key passphrase unlocks the encryption subkey.\n"
else
  printf "FAIL  Key passphrase did not unlock the encryption subkey.\n"
  exit 1
fi
unset key_passphrase

printf "\nBackup is recoverable.\n"
