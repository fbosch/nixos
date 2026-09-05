{ inputs, stdenv }:

import ../../../../lib/mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "inset-border";
  version = "0.3.0";
  src = ./.;
  description = "Configurable advanced-blend inset keylines for Hyprland windows";
  doCheck = true;
  extraFiles = [ ../common ];
}
