#!/usr/bin/env bash
set -euo pipefail

bootstrap_url="https://github.com/fbosch/nixos/raw/refs/heads/master/scripts/bootstrap/bootstrap-machine.sh"
tmp_script="$(mktemp)"

cleanup() {
  rm -f "$tmp_script"
}
trap cleanup EXIT

curl -fsSL "$bootstrap_url" -o "$tmp_script"

nix-shell -p gh git gum openssh qrencode --run "bash \"$tmp_script\""
