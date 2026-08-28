{ config, inputs, ... }:
{
  flake.modules.nixos = {
    vpn =
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
            default = "custom";
            description = ''
              DNS handling. "default" lets Mullvad's own resolvers handle DNS
              (10.64.0.1 programmed on wg0-mullvad with a `~.` routing domain);
              this gives a clean mullvad.net/check but bypasses the local
              dnsmasq funnel, so local zone overrides (Synology domain) do not
              apply while connected. "custom" points the tunnel DNS at the
              local dnsmasq funnel (customDnsServers) instead.
            '';
          };

          customDnsServers = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ "127.0.0.1" ];
            description = "DNS servers passed to `mullvad dns set custom` when dnsMode is \"custom\".";
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

    preservation =
      { config, lib, ... }:
      {
        config = lib.mkMerge [
          (lib.mkIf config.services.mullvad-vpn.enable {
            preservation.preserveAt."/persist".directories = [
              {
                directory = "/etc/mullvad-vpn";
                mode = "0755";
              }
            ];
          })
          (lib.mkIf config.services.tailscale.enable {
            preservation.preserveAt."/persist".directories = [
              {
                directory = "/var/lib/tailscale";
                mode = "0700";
              }
            ];
          })
        ];
      };
  };

  perSystem =
    { lib, system, ... }:
    let
      persistencePaths =
        { mullvad ? false
        , tailscale ? false
        ,
        }:
        let
          evaluated = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.preservation.nixosModules.preservation
              config.flake.modules.nixos.preservation
              {
                system.stateVersion = "25.05";
                services = {
                  mullvad-vpn.enable = mullvad;
                  tailscale.enable = tailscale;
                };
              }
            ];
          };
        in
        map
          (value: {
            inherit (value) directory mode;
          })
          (evaluated.config.preservation.preserveAt."/persist".directories or [ ]);
    in
    {
      nix-unit.tests.vpnPreservation = lib.optionalAttrs (system == "x86_64-linux") {
        testDisabledServicesContributeNothing = {
          expr = persistencePaths { };
          expected = [ ];
        };

        testMullvadOwnsDaemonState = {
          expr = persistencePaths { mullvad = true; };
          expected = [
            {
              directory = "/etc/mullvad-vpn";
              mode = "0755";
            }
          ];
        };

        testTailscaleOwnsDaemonState = {
          expr = persistencePaths { tailscale = true; };
          expected = [
            {
              directory = "/var/lib/tailscale";
              mode = "0700";
            }
          ];
        };
      };
    };
}
