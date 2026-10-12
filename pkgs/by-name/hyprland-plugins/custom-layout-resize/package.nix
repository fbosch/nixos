{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "custom-layout-resize";
  version = "0.4.0";
  src = ./.;
  description = "Native pointer-driven drag resize for custom Hyprland Lua layouts";
}
