{ inputs, withSystem, ... }:

{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
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
          inputs.nix-bwrapper.overlays.default
          inputs.self.overlays.chromium-webapps-hardening
        ];
      };
      enableByNameLegacy = pkgs.stdenv.isLinux;
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
        let
          evaluated = builtins.tryEval value;
        in
        if !evaluated.success then
          { }
        else if lib.isDerivation evaluated.value then
          {
            ${lib.concatStringsSep separator path} = evaluated.value;
          }
        else if lib.isAttrs evaluated.value then
          lib.concatMapAttrs (name: flattenPkgs separator (path ++ [ name ])) evaluated.value
        else
          { };
    in
    {
      legacyPackages = lib.mkIf enableByNameLegacy (lib.mkForce byNameLegacyPackages);

      packages = lib.mkForce (
        let
          flatPackages = flattenPkgs "/" [ ] byNameLegacyPackages;
        in
        lib.filterAttrs (_: pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) flatPackages
      );
    };

  flake = {
    overlays.default =
      final: prev:
      let
        overlaySystem =
          if prev ? stdenv then
            prev.stdenv.hostPlatform.system
          else if final ? stdenv then
            final.stdenv.hostPlatform.system
          else
            null;
      in
      if overlaySystem == null then
        { }
      else
        withSystem overlaySystem (
          { config, ... }:
          {
            local = config.packages;
          }
        );

  };
}
