
{
	description = "rvn flake nixos";

	inputs = {
		nixpkgs.url = "nixpkgs/nixos-unstable";
		zen-browser.url = "github:0xc000022070/zen-browser-flake";
		zen-browser.inputs.nixpkgs.follows = "nixpkgs";
		zen-browser.inputs.home-manager.follows = "home-manager";
		home-manager = {
			url = "github:nix-community/home-manager";
			inputs.nixpkgs.follows = "nixpkgs";
		};
		dotfiles = { url = "github:fbosch/dotfiles"; flake = false; };
	};

	
	outputs = { nixpkgs, home-manager, dotfiles, zen-browser, ... } @ inputs: {
		nixosConfigurations.rvn = nixpkgs.lib.nixosSystem {
			system = "x86_64-linux";
			specialArgs = { inherit inputs; };
			modules = [
				./configuration.nix
				home-manager.nixosModules.home-manager
				{
					 home-manager = { 
						users.fbb = import ./home.nix;
						useGlobalPkgs = true;
						useUserPackages = true;
						extraSpecialArgs = { 
							inherit inputs;
							repoUrl = "https://github.com/fbosch/dotfiles.git"; 
							dotRev = dotfiles.rev; 
						};
						backupFileExtension = "backup";
					};
				}
			];
		};
	};
}
