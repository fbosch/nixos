#!/usr/bin/env bash

set -euo pipefail

gpg_key_id="fbb.privacy+gpg@protonmail.com"
backup_filename="gpg-private.asc.gpg"
backup_repo="${GPG_BACKUP_REPO:-fbosch/gpg-backup}"
backup_release_tag="backup"
dry_run="false"

usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--key-id <key-id>] [--repo <owner/name>]

Rotate the encrypted GPG backup stored as an asset on the '$backup_release_tag'
release of a private repo. Release assets are not part of git history, and
replacing the asset deletes the previous backup.

  --repo  Private repo holding the backup (default: $backup_repo, or GPG_BACKUP_REPO)
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
  gh auth login --web --scopes repo
}

# Uploading the backup to a public repo would publish it, so refuse anything else.
require_private_repo() {
  local visibility

  if ! visibility="$(gh repo view "$backup_repo" --json visibility --jq .visibility 2>/dev/null)"; then
    printf "Error: Cannot access repo '%s'. Create it as private first:\n" "$backup_repo"
    printf "  gh repo create %s --private --add-readme --disable-wiki --disable-issues\n" "$backup_repo"
    exit 1
  fi

  if [ "$visibility" != "PRIVATE" ]; then
    printf "Error: Repo '%s' is %s; the backup requires a private repo.\n" "$backup_repo" "$visibility"
    exit 1
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --dry-run)
    dry_run="true"
    shift
    ;;
  --key-id | --repo)
    if [ -z "${2:-}" ]; then
      printf "Error: %s requires a value.\n" "$1"
      exit 1
    fi
    if [ "$1" = "--key-id" ]; then
      gpg_key_id="$2"
    else
      backup_repo="$2"
    fi
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    printf "Error: Unknown argument: %s\n" "$1"
    usage
    exit 1
    ;;
  esac
done

printf "=== Rotate GPG Backup Release Asset ===\n\n"

require_command gh
require_command gpg
require_command xkcdpass

if ! gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
  printf "Error: Could not find local secret key '%s'.\n" "$gpg_key_id"
  exit 1
fi

ensure_gh_auth
require_private_repo

release_exists="false"
if gh release view "$backup_release_tag" --repo "$backup_repo" >/dev/null 2>&1; then
  release_exists="true"
  printf "Repo: %s (private, release '%s' exists)\n" "$backup_repo" "$backup_release_tag"
else
  printf "Repo: %s (private, release '%s' will be created)\n" "$backup_repo" "$backup_release_tag"
fi

tmp_dir="$(mktemp -d)"
tmp_exported="$tmp_dir/gpg-private.asc"
tmp_encrypted="$tmp_dir/$backup_filename"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

printf "Generating passphrase with xkcdpass...\n"
backup_passphrase="$(xkcdpass -n 7 -d '-' -C lower)"

printf "Exporting local secret key...\n"
gpg --batch --yes --armor --output "$tmp_exported" --export-secret-keys "$gpg_key_id"

printf "Encrypting exported key...\n"
printf "%s" "$backup_passphrase" | gpg \
  --batch \
  --yes \
  --pinentry-mode loopback \
  --passphrase-fd 0 \
  --armor \
  --symmetric \
  --cipher-algo AES256 \
  --output "$tmp_encrypted" \
  "$tmp_exported"

if [ "$dry_run" = "true" ]; then
  printf "\nDry run: no GitHub changes were made.\n"
  if [ "$release_exists" = "false" ]; then
    printf "Would create release '%s' in %s\n" "$backup_release_tag" "$backup_repo"
  fi
  printf "Would replace release asset %s in %s\n" "$backup_filename" "$backup_repo"
  printf "Generated passphrase: %s\n" "$backup_passphrase"
  exit 0
fi

if [ "$release_exists" = "false" ]; then
  printf "Creating release '%s'...\n" "$backup_release_tag"
  gh release create "$backup_release_tag" \
    --repo "$backup_repo" \
    --title "GPG backup" \
    --notes "Encrypted GPG key backup managed by rotate-gpg-release. Replaced on each rotation." \
    --latest=false
fi

# --clobber deletes the previous asset, so no earlier backup remains on the release.
printf "Uploading release asset...\n"
gh release upload "$backup_release_tag" "$tmp_encrypted" --repo "$backup_repo" --clobber

printf "\nUploaded: %s release '%s' asset %s\n" "$backup_repo" "$backup_release_tag" "$backup_filename"
printf "Generated passphrase: %s\n" "$backup_passphrase"
