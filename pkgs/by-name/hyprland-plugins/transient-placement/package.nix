{ inputs, stdenv }:

import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "transient-placement";
  version = "0.1.0";
  src = ./.;
  description = "Pre-layout centering policy for configured Hyprland transients";
  doCheck = true;
}
