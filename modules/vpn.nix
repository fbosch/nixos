{
  flake.modules.nixos.vpn =
    { pkgs, lib, ... }:
    {
      # Mullvad exposes no NixOS options for these daemon-persisted settings;
      # scripts/network/network-restore-dns.sh applies them to the running
      # daemon via the mullvad CLI, and scripts/network/network-recover.sh
      # mirrors them as recovery-safe fallbacks.
      options.services.mullvad-vpn.runtimeSettings = {
        allowLan = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Allow LAN traffic while the VPN is connected (needed for LAN DNS upstreams).";
        };

        lockdownMode = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Block all traffic while the VPN is disconnected.";
        };

        dnsMode = lib.mkOption {
          type = lib.types.enum [
            "default"
            "custom"
          ];
          default = "default";
          description = ''
            DNS handling. "default" disables Mullvad's DNS-leak protection so
            dnsmasq can reach the LAN resolvers while connected; the declarative
            dnsmasq chain is the leak control instead.
          '';
        };
      };

      config = {
        services = {
          startupPolicy.applications.vpn = {
            tier = lib.mkDefault "essential";
            units = [
              {
                name = "tailscaled.service";
                provider = "nixos";
              }
            ];
          };

          mullvad-vpn = {
            enable = true;
          };

          tailscale = {
            enable = true;
            useRoutingFeatures = "client";
          };
        };

        environment.systemPackages = with pkgs; [
          tailscale
          proton-vpn
        ];
      };
    };
}
