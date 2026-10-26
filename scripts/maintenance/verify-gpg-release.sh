#!/usr/bin/env bash

set -euo pipefail

backup_filename="gpg-private.asc.gpg"
backup_repo="${GPG_BACKUP_REPO:-fbosch/gpg-backup}"
backup_release_tag="backup"
verify_args=()

usage() {
  cat <<EOF
Usage: $0 [--backup-only] [--repo <owner/name>]

Download the GPG backup asset from the '$backup_release_tag' release of a private
repo and verify it with verify-gpg-gist --file.

  --backup-only  Skip the key passphrase check
  --repo         Private repo holding the backup (default: $backup_repo, or GPG_BACKUP_REPO)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --backup-only)
    verify_args+=("$1")
    shift
    ;;
  --repo)
    if [ -z "${2:-}" ]; then
      printf "Error: --repo requires a value.\n"
      exit 1
    fi
    backup_repo="$2"
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

if ! gh auth status >/dev/null 2>&1; then
  printf "Error: GitHub CLI is not authenticated; run 'gh auth login' first.\n"
  exit 1
fi

visibility="$(gh repo view "$backup_repo" --json visibility --jq .visibility)"
if [ "$visibility" != "PRIVATE" ]; then
  printf "Warning: Repo '%s' is %s; the backup should live in a private repo.\n\n" "$backup_repo" "$visibility"
fi

umask 077
work_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/verify-gpg-release.XXXXXX")"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

printf "Downloading %s from %s release '%s'...\n" "$backup_filename" "$backup_repo" "$backup_release_tag"
gh release download "$backup_release_tag" \
  --repo "$backup_repo" \
  --pattern "$backup_filename" \
  --dir "$work_dir"

asset_count="$(gh release view "$backup_release_tag" --repo "$backup_repo" --json assets --jq '.assets | length')"
if [ "$asset_count" != "1" ]; then
  printf "Warning: Release '%s' has %s assets; expected only %s.\n" "$backup_release_tag" "$asset_count" "$backup_filename"
fi

verify-gpg-gist "${verify_args[@]}" --file "$work_dir/$backup_filename"
