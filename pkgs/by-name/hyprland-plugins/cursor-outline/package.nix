{ inputs, stdenv }:

import ../../../../lib/mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "cursor-outline";
  version = "0.1.0";
  src = ./.;
  description = "Toggleable silhouette outline for Hyprland's software cursor";
}
