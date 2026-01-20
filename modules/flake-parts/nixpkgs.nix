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
    { config, lib, system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.default
          inputs.nix-webapps.overlays.lib
          inputs.nix-webapps.overlays.default
          inputs.self.overlays.chromium-webapps-hardening
        ];
      };
      enableByName = pkgs.stdenv.isLinux;
      flattenPkgs =
        separator: path: value:
        if lib.isDerivation value then
          {
            ${lib.concatStringsSep separator path} = value;
          }
        else if lib.isAttrs value then
          lib.concatMapAttrs (name: flattenPkgs separator (path ++ [ name ])) value
        else
          { };
    in
    {
      pkgsDirectory = if enableByName then ../../pkgs/by-name else null;

      _module.args.pkgs = pkgs;

      packages = lib.mkIf enableByName (lib.mkForce (
        let
          flatPackages = flattenPkgs config.pkgsNameSeparator [ ] config.legacyPackages;
        in
        lib.filterAttrs (_: pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) flatPackages
      ));
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
