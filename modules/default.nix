{ inputs, ... }:

{
  imports = [
    ./flake-parts/nixpkgs.nix
    ./hosts/rvn-vm.nix
  ];
}