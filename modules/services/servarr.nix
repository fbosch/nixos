_: {
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
        users = {
          groups = {
            media = { };
            prowlarr = { };
          };
          users = {
            bazarr.extraGroups = [
              "media"
              "users"
            ];
            prowlarr = {
              isSystemUser = true;
              group = "prowlarr";
              extraGroups = [
                "media"
                "users"
              ];
            };
            lidarr.extraGroups = [
              "media"
              "users"
            ];
            radarr.extraGroups = [
              "media"
              "users"
            ];
            sonarr.extraGroups = [
              "media"
              "users"
            ];
          };
        };

        services = {
          lidarr = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };

          sonarr = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };

          radarr = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };

          bazarr = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };

          prowlarr = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };

          jackett.enable = lib.mkDefault false;

          exposedPorts = lib.mkAfter [
            {
              service = "prowlarr";
              tcpPorts = [ 9696 ];
            }
          ];

          # Ananicy rules for Servarr services - all background downloaders/managers
          ananicy.customRules = [
            {
              name = "Radarr";
              type = "BG_CPUIO";
              nice = 10;
              ioclass = "idle";
            }
            {
              name = "Sonarr";
              type = "BG_CPUIO";
              nice = 10;
              ioclass = "idle";
            }
            {
              name = "Prowlarr";
              type = "BG_CPUIO";
              nice = 10;
              ioclass = "idle";
            }
          ];
        };
      };
    };
}
