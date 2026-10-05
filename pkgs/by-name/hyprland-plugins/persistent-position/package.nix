{ inputs, stdenv }:
import ../mk-hyprland-plugin.nix { inherit inputs stdenv; } {
  pname = "persistent-position";
  version = "0.2.0";
  src = ./.;
  description = "Opt-in native pre-layout floating window position persistence for Hyprland";
  doCheck = true;
}
