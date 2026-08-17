#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

export BOOTSTRAP_MACHINE_LIB_ONLY=true
# The source path is resolved dynamically from the repository root.
# shellcheck disable=SC1091
source "$repo_root/scripts/bootstrap-machine.sh"
unset BOOTSTRAP_MACHINE_LIB_ONLY

if (validate_name "." "Host name" >/dev/null 2>&1); then
  echo "validate_name accepted ." >&2
  exit 1
fi

if (validate_name ".." "Host name" >/dev/null 2>&1); then
  echo "validate_name accepted .." >&2
  exit 1
fi

cat >"$tmp_dir/configuration-source.nix" <<'EOF_CONFIGURATION'
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "bootstrap-test";
  system.stateVersion = "25.05";
}
EOF_CONFIGURATION

cat >"$tmp_dir/hardware-source.nix" <<'EOF_HARDWARE'
{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/bootstrap-test";
    fsType = "ext4";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
EOF_HARDWARE

render_host_module \
  desktop \
  bootstrap-test \
  desktop \
  x86_64-linux \
  "$tmp_dir/default.nix"
render_wrapped_nixos_module \
  "$tmp_dir/configuration-source.nix" \
  "hosts/bootstrap-test/configuration" \
  "$tmp_dir/configuration.nix" \
  true
render_wrapped_nixos_module \
  "$tmp_dir/hardware-source.nix" \
  "hosts/bootstrap-test/hardware" \
  "$tmp_dir/hardware.nix"

validate_generated_module "$tmp_dir/default.nix"
validate_generated_module "$tmp_dir/configuration.nix"
validate_generated_module "$tmp_dir/hardware.nix"

grep -Fq 'hosts."bootstrap-test"' "$tmp_dir/default.nix"
grep -Fq '"hosts/bootstrap-test/configuration"' "$tmp_dir/default.nix"
grep -Fq '"hosts/bootstrap-test/hardware"' "$tmp_dir/default.nix"
grep -Fq '"presets/desktop"' "$tmp_dir/default.nix"
grep -Fq 'flake.modules.nixos."hosts/bootstrap-test/configuration"' "$tmp_dir/configuration.nix"
grep -Fq 'flake.modules.nixos."hosts/bootstrap-test/hardware"' "$tmp_dir/hardware.nix"

if grep -Fq './hardware-configuration.nix' "$tmp_dir/configuration.nix"; then
  echo "configuration wrapper retained the legacy hardware import" >&2
  exit 1
fi

if grep -Fq 'home-manager.users' "$tmp_dir/default.nix"; then
  echo "host module retained manual Home Manager wiring" >&2
  exit 1
fi

printf 'bootstrap-machine generator check passed\n'
