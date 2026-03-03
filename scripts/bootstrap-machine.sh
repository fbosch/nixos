#!/usr/bin/env bash
set -euo pipefail

repo="fbosch/nixos"
target_dir="$HOME/nixos"
default_host_name="$(tr -d '\n' </etc/hostname)"

validate_name() {
  local value="$1"
  local label="$2"

  if [ -z "$value" ]; then
    gum style --foreground 1 "$label cannot be empty"
    exit 1
  fi

  if [[ "$value" =~ [^a-zA-Z0-9._-] ]]; then
    gum style --foreground 1 "$label may only contain letters, numbers, ., _, and -"
    exit 1
  fi
}

render_host_module() {
  local preset="$1"
  local host_name="$2"
  local machine_name="$3"
  local host_file="$4"

  local nixos_imports=""
  local hm_imports=""

  case "$preset" in
    minimal)
      nixos_imports=""
      hm_imports=""
      ;;
    desktop|server)
      nixos_imports="
          \"presets/${preset}\"
          \"secrets\""
      hm_imports="
          \"presets/${preset}\"
          \"secrets\""
      ;;
    *)
      gum style --foreground 1 "Unsupported preset: $preset"
      exit 1
      ;;
  esac

  cat >"$host_file" <<EOF
{ config, ... }:
let
  hostMeta = {
    name = "${host_name}";
    sshAlias = null;
    tailscale = null;
    local = null;
    sshPublicKey = null;
  };
in
{
  flake = {
    meta.hosts = [ hostMeta ];

    modules.nixos."hosts/${host_name}" = {
      imports = config.flake.lib.resolve [${nixos_imports}
        ../../machines/${machine_name}/configuration.nix
        ../../machines/${machine_name}/hardware-configuration.nix
      ];

      home-manager.users.\${config.flake.meta.user.username}.imports =
        config.flake.lib.resolveHm [${hm_imports}
      ];
    };
  };
}
EOF
}

if [ -d "$target_dir" ]; then
  gum style --foreground 1 "Error: $target_dir already exists"
  gum style --foreground 244 "Move it away or remove it, then run install again."
  exit 1
fi

if [ ! -f /etc/nixos/configuration.nix ] || [ ! -f /etc/nixos/hardware-configuration.nix ]; then
  gum style --foreground 1 "Error: expected /etc/nixos/configuration.nix and /etc/nixos/hardware-configuration.nix"
  gum style --foreground 244 "Run this from a freshly installed NixOS machine."
  exit 1
fi

if [ -z "$default_host_name" ]; then
  gum style --foreground 1 "Error: could not determine hostname from /etc/hostname"
  exit 1
fi

gum style --border rounded --padding "1 2" \
  "NixOS bootstrap" \
  "This flow will authenticate GitHub, clone $repo, copy /etc/nixos configs," \
  "and generate a host module template."

host_name="$(gum input --prompt "Host name: " --value "$default_host_name")"
machine_name="$(gum input --prompt "Machine name: " --value "$default_host_name" --placeholder "directory under machines/")"
preset="$(gum choose --header "Select host preset" "minimal" "desktop" "server")"

validate_name "$host_name" "Host name"
validate_name "$machine_name" "Machine name"

gum style --foreground 244 "Host name: $host_name"
gum style --foreground 244 "Machine name: $machine_name"
gum style --foreground 244 "Preset: $preset"

if gum confirm "Proceed with bootstrap?"; then
  :
else
  gum style --foreground 3 "Aborted."
  exit 0
fi

gum style --foreground 244 ""
gum style --foreground 244 "Authenticating GitHub CLI (device flow)."
gum style --foreground 244 "Use the printed code on another device (phone/laptop)."

if gh auth status >/dev/null 2>&1; then
  gum style --foreground 2 "GitHub CLI already authenticated."
else
  gh auth login --git-protocol ssh --web
fi

gum style --foreground 244 ""
gum style --foreground 244 "Cloning $repo into $target_dir"
gh repo clone "$repo" "$target_dir"

machine_dir="$target_dir/machines/$machine_name"
host_file="$target_dir/modules/hosts/$host_name.nix"

if [ -e "$host_file" ]; then
  if gum confirm "Host file $host_file exists. Overwrite?"; then
    :
  else
    gum style --foreground 3 "Aborted."
    exit 0
  fi
fi

if [ -e "$machine_dir/configuration.nix" ] || [ -e "$machine_dir/hardware-configuration.nix" ]; then
  if gum confirm "Machine files in $machine_dir already exist. Overwrite?"; then
    :
  else
    gum style --foreground 3 "Aborted."
    exit 0
  fi
fi

gum style --foreground 244 ""
gum style --foreground 244 "Copying machine config into $machine_dir"
mkdir -p "$machine_dir"
cp -f /etc/nixos/configuration.nix "$machine_dir/"
cp -f /etc/nixos/hardware-configuration.nix "$machine_dir/"

gum style --foreground 244 "Generating host module at $host_file"
render_host_module "$preset" "$host_name" "$machine_name" "$host_file"

cd "$target_dir"

gum style --foreground 244 ""
if gum confirm "Run first rebuild now? (sudo nixos-rebuild switch --flake .#$host_name)"; then
  sudo nixos-rebuild switch --flake ".#$host_name"
  rebuild_status="completed"
else
  rebuild_status="skipped"
fi

gum style --foreground 2 ""
gum style --foreground 2 "Bootstrap complete"

gum style --foreground 244 ""
gum style --foreground 244 "Next steps:"
gum style --foreground 244 "  1. Review and customize $host_file"
if [ "$rebuild_status" = "skipped" ]; then
  gum style --foreground 244 "  2. sudo nixos-rebuild switch --flake .#$host_name"
  gum style --foreground 244 "  3. ./scripts/bootstrap-age.sh"
  gum style --foreground 244 "  4. ./scripts/bootstrap-gpg.sh"
  gum style --foreground 244 "  5. sudo nixos-rebuild switch --flake .#$host_name"
else
  gum style --foreground 244 "  2. ./scripts/bootstrap-age.sh"
  gum style --foreground 244 "  3. ./scripts/bootstrap-gpg.sh"
  gum style --foreground 244 "  4. sudo nixos-rebuild switch --flake .#$host_name"
fi
