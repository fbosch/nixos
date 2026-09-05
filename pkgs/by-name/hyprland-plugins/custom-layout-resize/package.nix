{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "custom-layout-resize";
  version = "0.3.1";
  src = ./.;
  description = "Native pointer-driven drag resize for custom Hyprland Lua layouts";
}
