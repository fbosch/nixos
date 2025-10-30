{ inputs, withSystem, ... }:

{
  systems = [ "x86_64-linux" ];

  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
  ];

  perSystem = { system, ... }: {
    pkgsDirectory = ../../pkgs/by-name;
    
    _module.args.pkgs = import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        inputs.self.overlays.default
        inputs.nix-webapps.overlays.lib
        inputs.nix-webapps.overlays.default
      ];
    };
  };

  flake = {
    overlays.default = final: prev:
      withSystem prev.stdenv.hostPlatform.system (
        { config, ... }:
        {
          local = config.packages;
          buildNpmGlobalPackage = import "${inputs.self}/pkgs/lib/buildNpmGlobalPackage.nix" { pkgs = final; };
        }
      );
  };
}