{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = {
      url = "github:fbosch/dotfiles";
      flake = false;
    };
    flake-parts.url = "github:hercules-ci/flake-parts";
    flatpaks.url = "github:gmodena/nix-flatpak";
    hyprland = {
      url = "github:hyprwm/Hyprland?submodules=1&ref=v0.51.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland-plugins = {
      url = "github:hyprwm/hyprland-plugins";
      inputs.hyprland.follows = "hyprland";
    };
    hyprland-contrib = {
      url = "github:hyprwm/contrib";
      inputs.nixpkgs.follows = "nixpkgs";
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
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
      flake-parts,
      flatpaks,
      dotfiles,
      ...
    }:
    let
      primarySystem = "x86_64-linux";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ primarySystem ];

      flake = {
        nixosConfigurations.rvn-vm = nixpkgs.lib.nixosSystem {
          system = primarySystem;
          specialArgs = {
            inherit inputs;
            system = primarySystem;
          };
          modules = [
            ./hosts/virtualbox-vm/configuration.nix
            ./hosts/virtualbox-vm/hardware-configuration.nix
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = "hm-backup";
                users.fbb = import ./home.nix;
                extraSpecialArgs = {
                  inherit inputs;
                  system = primarySystem;
                };
              };
            }
          ];
        };
      };
    };
}
