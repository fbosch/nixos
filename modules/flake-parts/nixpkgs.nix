{ inputs, withSystem, ... }:

{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./overlays/chromium-webapps-hardening.nix
  ];

  perSystem =
    { system, ... }:
    {
      pkgsDirectory = ../../pkgs/by-name;

      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.default
          inputs.nix-webapps.overlays.lib
          inputs.nix-webapps.overlays.default
          inputs.self.overlays.chromium-webapps-hardening
        ];
      };
    };

  flake = {
    overlays.default =
      final: prev:
      withSystem prev.stdenv.hostPlatform.system (
        { config, ... }:
        {
          local = config.packages // { };
          buildNpmGlobalPackage = import "${inputs.self}/pkgs/lib/buildNpmGlobalPackage.nix" {
            pkgs = final;
          };
        }
      );

  };
}
