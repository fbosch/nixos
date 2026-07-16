#!/usr/bin/env bash
# Re-encrypt all repository SOPS secret files with current .sops.yaml keys.

set -euo pipefail

if [ ! -f .sops.yaml ]; then
	echo "Error: .sops.yaml not found. Run from repository root." >&2
	exit 1
fi

if [ -z "${SOPS_AGE_KEY_FILE:-}" ] && [ -r "$HOME/.config/sops/age/keys.txt" ]; then
	export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
fi

if [ -r /dev/tty ]; then
	export GPG_TTY="$(tty)"
fi

shopt -s nullglob
secret_files=(secrets/*.yaml)
shopt -u nullglob

if [ ${#secret_files[@]} -eq 0 ]; then
	echo "No secret YAML files found under secrets/."
	exit 0
fi

temporary_root=$(mktemp -d)
cleanup() {
	rm -rf "$temporary_root"
}
trap cleanup EXIT

mkdir "$temporary_root/secrets"
cp .sops.yaml "$temporary_root/.sops.yaml"
cp "${secret_files[@]}" "$temporary_root/secrets/"

echo "Updating SOPS keys for ${#secret_files[@]} files..."
for file in "${secret_files[@]}"; do
	temporary_file="$temporary_root/$file"
	echo "  - $file"
	SOPS_CONFIG="$temporary_root/.sops.yaml" sops updatekeys --yes "$temporary_file"
done

cp "$temporary_root"/secrets/*.yaml secrets/

echo "Done."
echo "Next: run darwin-rebuild/nixos-rebuild switch to apply."
