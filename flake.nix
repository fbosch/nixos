{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    waybar-nixos-updates.url = "github:fbosch/waybar-nixos-updates";
    flatpaks.url = "github:gmodena/nix-flatpak";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland?submodules=1&ref=v0.51.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hy3 = {
      url = "github:outfoxxed/hy3?ref=hl0.51.0";
      inputs.hyprland.follows = "hyprland";
    };
    hyprspace = {
      url = "github:KZDKM/Hyprspace";
      inputs.hyprland.follows = "hyprland";
    };
    mac-style-plymouth = {
      url = "github:SergioRibera/s4rchiso-plymouth-theme";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    distro-grub-themes = {
      url = "github:AdisonCavani/distro-grub-themes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, flatpaks, ... }@inputs:
    let system = "x86_64-linux";
    in {
      nixosConfigurations = {
        rvn-vm = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs system; };
          modules = [
            ./hosts/virtualbox-vm/configuration.nix
            ./hosts/virtualbox-vm/hardware-configuration.nix
            home-manager.nixosModules.home-manager
            flatpaks.nixosModules.nix-flatpak
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "hm-backup";
              home-manager.users.fbb = import ./home.nix;
              home-manager.extraSpecialArgs = { inherit inputs system; };
            }
          ];
        };
      };
    };
}
