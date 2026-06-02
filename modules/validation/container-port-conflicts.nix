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
            conflicts = config.flake.lib.portConflicts.report config.services.exposedPorts;
          in
          [
            {
              assertion = !conflicts.tcp.hasConflicts;
              message = ''
                Services have conflicting TCP ports:
                ${conflicts.tcp.message}
              '';
            }
            {
              assertion = !conflicts.udp.hasConflicts;
              message = ''
                Services have conflicting UDP ports:
                ${conflicts.udp.message}
              '';
            }
          ];
      };
    };
}
