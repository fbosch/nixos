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
        ];
      };
      enableByNameLegacy = pkgs.stdenv.hostPlatform.isUnix;
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
          bunVersion = "1.4.0";
          bunSources = {
            "aarch64-darwin" = prev.fetchurl {
              url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-darwin-aarch64.zip";
              hash = "sha256-xmnpf2Fk4cluBwF0jbmN+ndJKQjL2DlMdVcTSnNd44E=";
            };
            "aarch64-linux" = prev.fetchurl {
              url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-linux-aarch64.zip";
              hash = "sha256-SxozLuhhmD65O8/m93D/+U4+MbLDiL2uo8jtNeWO7Q4=";
            };
            "x86_64-linux" = prev.fetchurl {
              url = "https://github.com/oven-sh/bun/releases/download/bun-v${bunVersion}/bun-linux-x64-baseline.zip";
              hash = "sha256-GE+0WV8NQBohfPfHjBvEMLqDMU2reouUgFurv3+nCX8=";
            };
          };
        in
        localOverlay
        // {
          ananicy-cpp = prev.ananicy-cpp.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/platform/linux/backtrace.cpp \
                --replace-fail '#include <cstdlib>' $'#include <cstdint>\n#include <cstdlib>'
                substituteInPlace src/utility/argument_parsing/argument.cpp \
                  --replace-fail '#include <cstdlib>' $'#include <cstdint>\n#include <cstring>\n#include <cstdlib>'
              substituteInPlace src/platform/linux/singleton_process.cpp \
                --replace-fail '#include <cerrno>' $'#include <cerrno>\n#include <cstdint>\n#include <cstring>'
            '';
          });
          bun =
            if prev.lib.versionAtLeast prev.bun.version "1.4.0" then
              prev.bun
            else
              prev.bun.overrideAttrs (old: {
                version = bunVersion;
                src =
                  bunSources.${prev.stdenvNoCC.hostPlatform.system}
                    or (throw "Unsupported system: ${prev.stdenvNoCC.hostPlatform.system}");
                passthru = old.passthru // {
                  sources = bunSources;
                };
              });
        };

  };
}
