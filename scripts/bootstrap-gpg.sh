#!/usr/bin/env bash
# Bootstrap GPG key from an encrypted secret gist
# Usage: ./scripts/bootstrap-gpg.sh [gist-id]
# If no gist ID is provided, resolves it by searching your gists for the
# expected filename (requires gh auth).

set -euo pipefail

gpg_key_id="fbb.privacy+gpg@protonmail.com"
gpg_gist_filename="gpg-private.asc.gpg"

resolve_gist_ids() {
	gh gist list --limit 100 2>/dev/null | awk -F'\t' -v name="$gpg_gist_filename" 'index($3, name) || index($2, name) { print $1 }'
}

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

if gh auth status >/dev/null 2>&1; then
	printf "GitHub CLI already authenticated.\n"
else
	printf "Authenticating GitHub CLI (device flow).\n"
	printf "Open: https://github.com/login/device?skip_account_picker=true\n"
	gh auth login --web --scopes gist
fi

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

if gpg --batch --yes --pinentry-mode loopback --passphrase "$gpg_backup_passphrase" --import "$tmp_decrypted" 2>&1; then
	printf "GPG key imported successfully.\n"
else
	printf "Error: Failed to decrypt or import GPG key from gist.\n"
	printf "Check passphrase and gist content.\n"
	exit 1
fi
unset gpg_backup_passphrase

printf "\nSetting ultimate trust for GPG key...\n"
if printf "trust\n5\ny\nquit\n" | gpg --command-fd 0 --edit-key "$gpg_key_id" >/dev/null 2>&1; then
	printf "GPG key configured with ultimate trust.\n"
else
	printf "Warning: Failed to set trust level automatically.\n"
	printf "Run manually: gpg --edit-key %s\n" "$gpg_key_id"
fi

printf "\n=== Bootstrap Complete ===\n\n"
printf "GPG key is now available for manual secret editing.\n"
