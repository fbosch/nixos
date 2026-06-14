{ config, lib, ... }:
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

    lazyApp =
      pkgs: pkgOrArgs:
      pkgs.lazy-app.override (if lib.isDerivation pkgOrArgs then { pkg = pkgOrArgs; } else pkgOrArgs);

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
  };
}
