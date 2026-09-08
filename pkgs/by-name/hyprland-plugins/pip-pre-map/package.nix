{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "pip-pre-map";
  version = "0.1.0";
  src = ./.;
  description = "Preserve client-selected initial sizing for browser PiP windows";
}
