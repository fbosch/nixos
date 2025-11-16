{ inputs, withSystem, ... }:

{
  systems = [ "x86_64-linux" "aarch64-linux" ];

  imports = [
    inputs.pkgs-by-name-for-flake-parts.flakeModule
    ./overlays/chromium-webapps-hardening.nix
    ./overlays/proton-core-fix.nix
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
        inputs.self.overlays.chromium-webapps-hardening
        inputs.self.overlays.proton-core-fix
      ];
    };
  };

  flake = {
    overlays.default = final: prev:
      withSystem prev.stdenv.hostPlatform.system (
        { config, ... }:
        {
          local = config.packages // { };
          buildNpmGlobalPackage = import "${inputs.self}/pkgs/lib/buildNpmGlobalPackage.nix" { pkgs = final; };
        }
      );

  };
}
