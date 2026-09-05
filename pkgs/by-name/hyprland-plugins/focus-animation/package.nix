{ inputs, stdenv }:

import ../../../../lib/mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "focus-animation";
  version = "0.1.10";
  src = ./.;
  description = "Native focus animation leaf for Hyprland";
  doCheck = true;
}
