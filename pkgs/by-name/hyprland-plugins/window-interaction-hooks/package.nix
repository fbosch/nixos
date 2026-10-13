{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "window-interaction-hooks";
  version = "0.3.0";
  src = ./.;
  description = "Native live and completed window interaction events for Hyprland";
}
