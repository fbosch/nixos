#!/usr/bin/env bash
set -euo pipefail

repo="fbosch/nixos"
target_dir="$HOME/nixos"
host_name="$(tr -d '\n' </etc/hostname)"

if [ -d "$target_dir" ]; then
  printf "Error: %s already exists.\n" "$target_dir"
  printf "Move it away or remove it, then run install again.\n"
  exit 1
fi

if [ ! -f /etc/nixos/configuration.nix ] || [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  printf "Error: expected /etc/nixos/configuration.nix and /etc/nixos/hardware-configuration.nix\n"
  printf "Run this from a freshly installed NixOS machine.\n"
  exit 1
fi

if [ -z "$host_name" ]; then
  printf "Error: could not determine hostname from /etc/hostname\n"
  exit 1
fi

printf "Authenticating GitHub CLI (device flow).\n"
printf "Use the printed code on another device (phone/laptop) to complete login.\n\n"

if gh auth status >/dev/null 2>&1; then
  printf "GitHub CLI already authenticated.\n"
else
  gh auth login --git-protocol ssh --web
fi

printf "\nCloning %s into %s\n" "$repo" "$target_dir"
gh repo clone "$repo" "$target_dir"

machine_dir="$target_dir/machines/$host_name"
printf "\nCopying machine config into %s\n" "$machine_dir"
mkdir -p "$machine_dir"
cp /etc/nixos/configuration.nix "$machine_dir/"
cp /etc/nixos/hardware-configuration.nix "$machine_dir/"

printf "\nBootstrap complete.\n\n"
printf "Next steps:\n"
printf "  1. Create modules/hosts/%s.nix using an existing host as template.\n" "$host_name"
printf "  2. cd %s\n" "$target_dir"
printf "  3. sudo nixos-rebuild switch --flake .#%s\n" "$host_name"
printf "  4. ./scripts/bootstrap-age.sh\n"
printf "  5. ./scripts/bootstrap-gpg.sh\n"
printf "  6. sudo nixos-rebuild switch --flake .#%s\n" "$host_name"
