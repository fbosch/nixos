#!/usr/bin/env bash

set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

extract_fish_config() {
  local activation_script=$1
  local fish_config=$2
  local copying=false
  local line

  while IFS= read -r line; do
    if [[ $line == *"<< 'EOF'" ]]; then
      copying=true
      continue
    fi

    if [ "$line" = "EOF" ]; then
      break
    fi

    if [ "$copying" = true ]; then
      printf '%s\n' "$line"
    fi
  done <"$activation_script" >"$fish_config"

  if [ "$copying" = false ]; then
    printf 'Fish configuration heredoc was not found in %s\n' "$activation_script" >&2
    return 1
  fi
}

check_activation() {
  local name=$1
  local attr=$2
  local activation_script="$tmpdir/$name.sh"
  local fish_config="$tmpdir/$name.fish"

  nix eval --no-write-lock-file --raw "$attr" >"$activation_script"
  shellcheck --shell=sh -S error "$activation_script"
  extract_fish_config "$activation_script" "$fish_config"
  fish --no-execute "$fish_config"
}

check_activation \
  darwin \
  '.#darwinConfigurations.kmd-mac.config.home-manager.users.Z6FBO.home.activation.generateFishPrivateConfig.data'
check_activation \
  nixos \
  '.#nixosConfigurations.rvn-pc.config.home-manager.users.fbb.home.activation.generateFishPrivateConfig.data'
