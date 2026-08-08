#!/usr/bin/env bash

set -euo pipefail

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
repo_url="git+file://$(git rev-parse --show-toplevel)"

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
  local host_name=$2
  local host_system=$3
  local username=$4
  local home_directory=$5
  local state_version=$6
  local include_secrets=$7
  local expected_host_variable=$8
  local activation_script="$tmpdir/$name.sh"
  local fish_config="$tmpdir/$name.fish"

  nix eval --no-write-lock-file --impure --raw --expr "
    let
      flake = builtins.getFlake \"$repo_url\";
      pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
      hostMeta = {
        name = \"$host_name\";
        system = \"$host_system\";
      };
      homeManager = flake.inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        extraSpecialArgs = { inherit hostMeta; };
        modules =
          [ flake.modules.homeManager.shell ]
          ++ pkgs.lib.optional $include_secrets flake.modules.homeManager.secrets
          ++ [
            {
              home = {
                username = \"$username\";
                homeDirectory = \"$home_directory\";
                stateVersion = \"$state_version\";
              };
            }
          ];
      };
    in
      homeManager.config.home.activation.generateFishPrivateConfig.data
  " >"$activation_script"
  shellcheck --shell=sh -S error "$activation_script"
  extract_fish_config "$activation_script" "$fish_config"
  fish --no-execute "$fish_config"

  case $(<"$fish_config") in
  *"set -gx $expected_host_variable"*) ;;
  *)
    printf 'Expected %s in generated Fish configuration for %s\n' "$expected_host_variable" "$host_name" >&2
    return 1
    ;;
  esac
}

check_activation \
  darwin \
  kmd-mac \
  aarch64-darwin \
  Z6FBO \
  /Users/Z6FBO \
  25.05 \
  false \
  NH_DARWIN_HOST
check_activation \
  nixos \
  rvn-pc \
  x86_64-linux \
  fbb \
  /home/fbb \
  25.05 \
  true \
  NH_OS_HOST
