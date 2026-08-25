#!/usr/bin/env bash
set -euo pipefail

github_device_url="https://github.com/login/device?skip_account_picker=true"

if ! command -v qrencode >/dev/null 2>&1; then
  printf 'Error: qrencode is required.\n' >&2
  printf "Run this probe with: nix-shell -p qrencode --run 'bash scripts/bootstrap/show-github-device-qr.sh'\n" >&2
  exit 1
fi

printf 'GitHub device login:\n%s\n\n' "$github_device_url"
qrencode \
  --type=ANSIUTF8 \
  --level=M \
  --margin=4 \
  --output=- \
  -- "$github_device_url"
