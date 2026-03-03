#!/usr/bin/env bash
set -euo pipefail

bootstrap_url="https://raw.githubusercontent.com/fbosch/nixos/main/scripts/bootstrap-machine.sh"
tmp_script="$(mktemp)"

cleanup() {
  rm -f "$tmp_script"
}
trap cleanup EXIT

curl -fsSL "$bootstrap_url" -o "$tmp_script"

nix-shell -p gh git gum --run "bash \"$tmp_script\""
