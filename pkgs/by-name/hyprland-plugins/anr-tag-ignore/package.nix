{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "anr-tag-ignore";
  version = "0.1.0";
  src = ./.;
  description = "Suppress Hyprland ANR state for windows carrying configured tags";
}
