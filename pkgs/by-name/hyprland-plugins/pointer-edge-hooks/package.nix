{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "pointer-edge-hooks";
  version = "0.1.0";
  src = ./.;
  description = "Native bottom-edge pointer zones for a Hyprland Waybar controller";
}
