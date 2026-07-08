{ inputs, withSystem, ... }:

{
  systems = [
    "x86_64-linux"
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
          inputs.nix-bwrapper.overlays.default
          inputs.lazy-apps.overlays.default
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
        if enableByNameLegacy then
          let
            flatPackages = flattenPkgs "/" [ ] byNameLegacyPackages;
          in
          lib.filterAttrs (_: pkg: lib.meta.availableOn pkgs.stdenv.hostPlatform pkg) flatPackages
        else
          { }
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
        let
          localOverlay = withSystem overlaySystem (
            { config, ... }:
            {
              local = config.packages;
            }
          );
          bitwardenDesktopElectronWorkaround = prev.lib.optionalAttrs prev.stdenv.hostPlatform.isLinux {
            # WORKAROUND: bitwarden-desktop still depends on EOL Electron 39.
            # Use electron_39-bin to avoid compiling insecure EOL Electron from source.
            # nixpkgs#521305 tracks Electron 39 EOL; nixpkgs#526914 tracks bitwarden-desktop specifically.
            # Upstream bump: https://github.com/bitwarden/clients/pull/20448
            # REMOVAL CONDITION: remove when bitwarden-desktop builds on Electron >= 40 in nixpkgs.
            bitwarden-desktop = prev.bitwarden-desktop.override {
              electron_39 = final.electron_39-bin;
            };
          };
        in
        localOverlay // bitwardenDesktopElectronWorkaround;

  };
}
