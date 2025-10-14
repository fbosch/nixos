{
  description = "NixOS Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flatpaks.url = "github:gmodena/nix-flatpak";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = { url = "github:fbosch/dotfiles/master"; flake = false; };
    # elephant = { 
    #   url = "github:abenz1267/elephant"; 
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };
    # walker = {
    #   url = "github:abenz1267/walker";
    #   inputs.nixpkgs.follows = "nixpkgs";
    #   inputs.elephant.follows = "elephant";
    # };
  };

  outputs = { self, nixpkgs, home-manager, flatpaks, ...  } @ inputs: 
  let 
   system = "x86_64-linux";
  in {
      nixosConfigurations = {
        rvn-vm = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./hosts/virtualbox-vm/configuration.nix
            ./hosts/virtualbox-vm/hardware-configuration.nix
             home-manager.nixosModules.home-manager
	     flatpaks.nixosModules.nix-flatpak
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.fbb = import ./home.nix;
              home-manager.extraSpecialArgs = {
                inherit inputs system;
              };
            }
          ];
        };
      };
    };
}
