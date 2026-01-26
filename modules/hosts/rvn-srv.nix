{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";
    modules = [
      "secrets"
      "nas"
      "services/home-assistant"
      "services/termix"
      "services/komodo"
      "services/plex"
      "services/servarr"
      "virtualization/podman"
      "system/scheduled-suspend"
    ];

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
      inputs.nixos-hardware.nixosModules.common-cpu-intel
      (
        { config
        , pkgs
        , lib
        , ...
        }:
        {
          environment.systemPackages = [
            pkgs.xclip
            pkgs.xsel
          ];

          services.termix = {
            enable = true;
            port = 7310;
          };

          services.komodo = {
            enable = true;
            core.host = "https://komodo.corvus-corax.synology.me";
            core.allowSignups = false;
            periphery.requirePasskey = false;
          };

          services.plex.enable = true;

          sops.templates."atticd-env" = {
            content = "ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder.atticd-jwt}\n";
            mode = "0400";
          };

          services.atticd = {
            enable = true;
            environmentFile = config.sops.templates."atticd-env".path;
            settings = {
              listen = "0.0.0.0:8081";
              allowed-hosts = [ "attic.corvus-corax.synology.me" ];
              api-endpoint = "https://attic.corvus-corax.synology.me/";
              substituter-endpoint = "https://attic.corvus-corax.synology.me/";
              storage = {
                type = "local";
                path = "/mnt/nas/web/attic";
              };
            };
          };

          systemd.services.atticd = {
            unitConfig.RequiresMountsFor = [
              "/mnt/nas/web"
              "/mnt/nas/web/attic"
            ];
            after = [ "mnt-nas-web.mount" ];
          };

          services.uptime-kuma.enable = true;
          services.uptime-kuma.settings.HOST = "0.0.0.0";

          networking.firewall.allowedTCPPorts = [
            3001
            8081
          ];

          systemd.tmpfiles.rules = [
            "d /mnt/nas/web/attic 0750 atticd atticd -"
          ];

          sops.secrets.atticd-jwt = {
            mode = "0400";
          };

          powerManagement.scheduledSuspend = {
            enable = true;
            schedules = {
              weekday = {
                suspendTime = "23:30";
                wakeTime = "05:30";
                days = "Mon,Tue,Wed,Thu,Fri";
              };
              weekend = {
                suspendTime = "02:00";
                wakeTime = "07:30";
                days = "Sat,Sun";
              };
            };
          };
        }
      )
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  flake.modules.nixos."hosts/rvn-srv" = hostResult._module;

  flake.hostConfigs.rvn-srv = hostResult._hostConfig;
}
