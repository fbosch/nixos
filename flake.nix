{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = { url = "github:fbosch/dotfiles/master"; flake = false; };
    elephant.url = "github:abenz1267/elephant";
    walker = {
      url = "github:abenz1267/walker";
      inputs.elephant.follows = "elephant";
    };
  };

  outputs = { self, nixpkgs, dotfiles, home-manager, zen-browser, elephant, walker } @ inputs: 
    {
      nixosConfigurations = {
        rvn-vm = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/virtualbox-vm/configuration.nix
            ./hosts/virtualbox-vm/hardware-configuration.nix
             home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.fbb = import ./home.nix;
              home-manager.extraSpecialArgs = {
                inherit zen-browser dotfiles walker;
                dotfilesUrl = "https://github.com/fbosch/dotfiles.git";
              };
            }
          ];
        };
      };
    };
}
