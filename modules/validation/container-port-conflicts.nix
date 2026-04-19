_: {
  flake.modules.nixos."validation/container-port-conflicts" =
    { config
    , lib
    , ...
    }:
    {
      options.services.exposedPorts = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              service = lib.mkOption {
                type = lib.types.str;
                description = "Service identifier for port validation";
              };
              tcpPorts = lib.mkOption {
                type = lib.types.listOf lib.types.port;
                default = [ ];
                description = "TCP ports used by the service";
              };
              udpPorts = lib.mkOption {
                type = lib.types.listOf lib.types.port;
                default = [ ];
                description = "UDP ports used by the service";
              };
            };
          }
        );
        default = [ ];
        description = "Declared service ports for conflict checks";
      };

      config = {
        assertions =
          let
            tcpPorts = lib.flatten (
              map
                (
                  svc:
                  map
                    (port: {
                      inherit (svc) service;
                      inherit port;
                    })
                    svc.tcpPorts
                )
                config.services.exposedPorts
            );

            udpPorts = lib.flatten (
              map
                (
                  svc:
                  map
                    (port: {
                      inherit (svc) service;
                      inherit port;
                    })
                    svc.udpPorts
                )
                config.services.exposedPorts
            );

            # Helper function to find duplicate ports
            findDuplicates =
              portList:
              let
                # Group by port number
                grouped = builtins.groupBy (item: toString item.port) portList;

                # Find groups with more than one entry
                duplicates = lib.filterAttrs (_port: items: (lib.length items) > 1) grouped;
              in
              duplicates;

            tcpDuplicates = findDuplicates tcpPorts;
            udpDuplicates = findDuplicates udpPorts;

            # Format duplicate port info for error messages
            formatDuplicates =
              protocol: dups:
              lib.concatStringsSep "\n" (
                lib.mapAttrsToList
                  (
                    port: items: "  ${protocol} port ${port}: ${lib.concatMapStringsSep ", " (i: i.service) items}"
                  )
                  dups
              );

          in
          [
            {
              assertion = tcpDuplicates == { };
              message = ''
                Services have conflicting TCP ports:
                ${formatDuplicates "TCP" tcpDuplicates}
              '';
            }
            {
              assertion = udpDuplicates == { };
              message = ''
                Services have conflicting UDP ports:
                ${formatDuplicates "UDP" udpDuplicates}
              '';
            }
          ];
      };
    };
}
