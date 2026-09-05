{ inputs, stdenv }:

import ../../../../lib/mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "adaptive-soft-shadow";
  version = "0.2.2";
  src = ./.;
  description = "Configurable advanced-blend shadows for Hyprland windows";
  doCheck = true;
  extraFiles = [ ../common ];
}
