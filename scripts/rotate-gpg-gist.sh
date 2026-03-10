#!/usr/bin/env bash

set -euo pipefail

gpg_key_id="fbb.privacy+gpg@protonmail.com"
gpg_gist_filename="gpg-private.asc.gpg"
dry_run="false"

usage() {
	cat <<EOF
Usage: $0 [--dry-run] [--key-id <key-id>]

Rotate the encrypted GPG backup gist using the current local secret key.
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

ensure_gist_scope() {
	if gh gist list --limit 1 >/dev/null 2>&1; then
		return
	fi

	printf "Refreshing GitHub auth scopes for gist access.\n"
	gh auth refresh -h github.com -s gist
}

list_matching_gist_ids() {
	gh gist list --limit 100 2>/dev/null | awk -F'\t' -v name="$gpg_gist_filename" '
		index($3, name) || index($2, name) { print $1 }
	'
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--dry-run)
			dry_run="true"
			shift
			;;
		--key-id)
			if [ -z "${2:-}" ]; then
				printf "Error: --key-id requires a value.\n"
				exit 1
			fi
			gpg_key_id="$2"
			shift 2
			;;
		-h|--help)
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

printf "=== Rotate GPG Backup Gist ===\n\n"

require_command gh
require_command gpg
require_command xkcdpass

if gpg --list-secret-keys "$gpg_key_id" >/dev/null 2>&1; then
	:
else
	printf "Error: Could not find local secret key '%s'.\n" "$gpg_key_id"
	exit 1
fi

ensure_gh_auth
ensure_gist_scope

mapfile -t matching_gists < <(list_matching_gist_ids)

if [ "${#matching_gists[@]}" -gt 1 ]; then
	printf "Error: Found multiple gists containing '%s'.\n" "$gpg_gist_filename"
	printf "Delete duplicates before rotating:\n"
	printf "  %s\n" "${matching_gists[@]}"
	exit 1
fi

old_gist_id=""
if [ "${#matching_gists[@]}" -eq 1 ]; then
	old_gist_id="${matching_gists[0]}"
	printf "Existing gist: %s\n" "$old_gist_id"
else
	printf "Existing gist: none\n"
fi

tmp_dir="$(mktemp -d)"
tmp_exported="$tmp_dir/gpg-private.asc"
tmp_encrypted="$tmp_dir/$gpg_gist_filename"

cleanup() {
	rm -rf "$tmp_dir"
}
trap cleanup EXIT

printf "Generating passphrase with xkcdpass...\n"
backup_passphrase="$(xkcdpass -n 5 -d '-' -C lower)"

printf "Exporting local secret key...\n"
gpg --batch --yes --armor --output "$tmp_exported" --export-secret-keys "$gpg_key_id"

printf "Encrypting exported key...\n"
printf "%s" "$backup_passphrase" | gpg \
	--batch \
	--yes \
	--pinentry-mode loopback \
	--passphrase-fd 0 \
	--symmetric \
	--cipher-algo AES256 \
	--output "$tmp_encrypted" \
	"$tmp_exported"

if [ "$dry_run" = "true" ]; then
	printf "\nDry run: no GitHub changes were made.\n"
	printf "Would create new gist from: %s\n" "$tmp_encrypted"
	if [ -n "$old_gist_id" ]; then
		printf "Would delete old gist after create: %s\n" "$old_gist_id"
	fi
	printf "Generated passphrase: %s\n" "$backup_passphrase"
	exit 0
fi

printf "Creating new secret gist...\n"
new_gist_url="$(gh gist create "$tmp_encrypted" --desc "$gpg_gist_filename")"

if [ -n "$old_gist_id" ]; then
	printf "Deleting old gist: %s\n" "$old_gist_id"
	gh gist delete "$old_gist_id"
fi

printf "\nCreated gist: %s\n" "$new_gist_url"
printf "Generated passphrase: %s\n" "$backup_passphrase"
