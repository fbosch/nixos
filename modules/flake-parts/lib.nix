{ inputs
, config
, lib
, ...
}:
{
  config.flake.lib = {
    # Dendritic pattern helpers for module path resolution
    # These helpers allow using string paths in imports while maintaining dendritic pattern compliance

    # Resolve NixOS module paths
    # Usage: imports = config.flake.lib.resolve [ "presets/server" "secrets" ../../hardware.nix ];
    resolve = builtins.map (m: if builtins.isString m then config.flake.modules.nixos.${m} else m);

    # Resolve Home Manager module paths
    # Usage: home-manager.users.username.imports = config.flake.lib.resolveHm [ "users" "dotfiles" ];
    resolveHm = builtins.map (
      m: if builtins.isString m then config.flake.modules.homeManager.${m} else m
    );

    # Resolve Darwin module paths
    # Usage: imports = config.flake.lib.resolveDarwin [ "security" "homebrew" ];
    resolveDarwin = builtins.map (
      m: if builtins.isString m then config.flake.modules.darwin.${m} else m
    );

    hostMeta =
      name:
      lib.findFirst
        (
          host: host.name == name
        )
        (throw "Host metadata `${name}` is not defined")
        config.flake.meta.hosts;

    lazyApp =
      pkgs: pkgOrArgs:
      pkgs.lazy-app.override (if lib.isDerivation pkgOrArgs then { pkg = pkgOrArgs; } else pkgOrArgs);

    lazyDesktopApp =
      pkgs:
      { pkg
      , desktopItem
      , exe ? null
      ,
      }:
      let
        desktopItem' =
          if
            desktopItem ? icon
            && builtins.isPath desktopItem.icon
            && lib.hasSuffix ".svg" (toString desktopItem.icon)
          then
            desktopItem
            // {
              icon = pkgs.runCommand "${desktopItem.name}-icon.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
                rsvg-convert --width 256 --height 256 ${desktopItem.icon} > "$out"
              '';
            }
          else
            desktopItem;
      in
      config.flake.lib.lazyApp pkgs (
        {
          inherit pkg;
          desktopItems = [ (pkgs.makeDesktopItem desktopItem') ];
        }
        // lib.optionalAttrs (exe != null) { inherit exe; }
      );

    themes.zenwritten =
      let
        # Zenbones palette role names: rose, leaf, wood, water, blossom, sky.
        # Hex values preserve this repo's existing Zenwritten console palette.
        base = {
          black = "000000";
          background = "191919";
          surface = "242424";
          rose = "d86659";
          leaf = "7aca6c";
          wood = "c69761";
          water = "5b64db";
          blossom = "b671a1";
          sky = "6baedb";
          stone = "bbbdc7";
        };

        bright = {
          black = "2a2a2a";
          rose = "e58073";
          leaf = "8ada7c";
          wood = "d6a771";
          water = "6b74eb";
          blossom = "c681b1";
          sky = "7bbefb";
          stone = "cbcbd5";
        };

        withHash = builtins.mapAttrs (_: value: "#${value}");
      in
      {
        inherit base bright;

        css = {
          base = withHash base;
          bright = withHash bright;
        };

        console = [
          base.black
          base.rose
          base.leaf
          base.wood
          base.water
          base.blossom
          base.sky
          base.stone
          bright.black
          bright.rose
          bright.leaf
          bright.wood
          bright.water
          bright.blossom
          bright.sky
          bright.stone
        ];
      };

    startupPolicy.quadlet =
      nixosConfig: unit:
      lib.attrByPath [
        "services"
        "startupPolicy"
        "quadletUnitSettings"
        unit
      ]
        (throw "startupPolicy Quadlet unit `${unit}` is not registered")
        nixosConfig;

    portConflicts =
      let
        portsFor =
          portsAttr: exposedPorts:
          lib.flatten (
            map
              (
                svc:
                map
                  (port: {
                    inherit (svc) service;
                    inherit port;
                  })
                  (svc.${portsAttr} or [ ])
              )
              exposedPorts
          );

        findDuplicates =
          portList:
          let
            grouped = builtins.groupBy (item: toString item.port) portList;
          in
          lib.filterAttrs (_port: items: (lib.length items) > 1) grouped;

        formatDuplicates =
          protocol: duplicates:
          lib.concatStringsSep "\n" (
            lib.mapAttrsToList
              (
                port: items: "  ${protocol} port ${port}: ${lib.concatMapStringsSep ", " (i: i.service) items}"
              )
              duplicates
          );

        reportFor =
          protocol: portsAttr: exposedPorts:
          let
            duplicates = findDuplicates (portsFor portsAttr exposedPorts);
          in
          {
            inherit duplicates;
            hasConflicts = duplicates != { };
            message = formatDuplicates protocol duplicates;
          };
      in
      {
        report =
          exposedPorts:
          let
            tcp = reportFor "TCP" "tcpPorts" exposedPorts;
            udp = reportFor "UDP" "udpPorts" exposedPorts;
          in
          {
            inherit tcp udp;
            hasConflicts = tcp.hasConflicts || udp.hasConflicts;
          };
      };

    sopsHelpers =
      let
        rootOnly = {
          mode = "0400";
        };

        wheelReadable = {
          mode = "0440";
          group = "wheel";
        };

        worldReadable = {
          mode = "0444";
        };

        mkSecretsWithOpts =
          sopsFile: opts: names:
          builtins.listToAttrs (
            builtins.map
              (name: {
                inherit name;
                value = lib.recursiveUpdate { inherit sopsFile; } opts;
              })
              names
          );

        mkSecrets = sopsFile: mkSecretsWithOpts sopsFile { };

        mkSecret = sopsFile: opts: lib.recursiveUpdate { inherit sopsFile; } opts;
      in
      {
        inherit
          rootOnly
          wheelReadable
          worldReadable
          mkSecrets
          mkSecretsWithOpts
          mkSecret
          ;
      };

    secretspecHelpers = {
      systemdCredentialScript =
        { config
        , scope
        , reason
        , command
        ,
        }:
        let
          secretspec =
            inputs.nixpkgs-unstable.legacyPackages.${config.nixpkgs.hostPlatform.system}.secretspec;
          manifestFile = builtins.toFile "secretspec.toml" (builtins.readFile ../../secretspec.toml);
        in
        ''
          exec ${
            lib.escapeShellArgs (
              [
                (lib.getExe secretspec)
                "--file"
                (toString manifestFile)
                "run"
                "--profile"
                "systemd"
                "--scope"
                scope
                "--reason"
                reason
                "--"
              ]
              ++ command
            )
          }
        '';
    };
  };
}
