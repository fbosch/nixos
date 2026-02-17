{ inputs, withSystem, ... }:

{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  imports = [
    ./overlays/chromium-webapps-hardening.nix
  ];

  perSystem =
    { config
    , lib
    , system
    , ...
    }:
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
      inputsScope = lib.makeScope pkgs.newScope (_self: {
        inherit inputs;
      });
      scopeFromDirectory =
        directory:
        lib.filesystem.packagesFromDirectoryRecursive {
          inherit directory;
          inherit (inputsScope) newScope callPackage;
        };
      scope = scopeFromDirectory ../../pkgs/by-name;
      extractPackages =
        currentScope:
        let
          shouldRecurse =
            lib.isAttrs currentScope
            && !(lib.isDerivation currentScope)
            && currentScope ? packages
            && lib.isFunction currentScope.packages;
          mappedSet = lib.mapAttrs (_: extractPackages) (currentScope.packages currentScope);
        in
        if shouldRecurse then mappedSet else currentScope;
      byNameLegacyPackages = extractPackages scope;
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
      legacyPackages = lib.mkIf enableByName (lib.mkForce byNameLegacyPackages);

      packages = lib.mkIf enableByName (
        lib.mkForce (
          let
            flatPackages = flattenPkgs "/" [ ] byNameLegacyPackages;
          in
          lib.filterAttrs (_: pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) flatPackages
        )
      );
    };

  flake = {
    overlays.default =
      final: prev:
      withSystem prev.stdenv.hostPlatform.system (
        { config, ... }:
        {
          local = config.packages;
          buildNpmGlobalPackage = import "${inputs.self}/pkgs/lib/buildNpmGlobalPackage.nix" {
            pkgs = final;
          };
        }
      );

  };
}
