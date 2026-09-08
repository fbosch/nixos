{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "adaptive-soft-shadow";
  version = "0.3.0";
  src = ./.;
  description = "Configurable advanced-blend shadows for Hyprland windows";
  doCheck = true;
  extraFiles = [ ../common ];
}
