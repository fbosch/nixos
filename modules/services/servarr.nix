_: {
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
        services.startupPolicy.applications.servarr = {
          tier = lib.mkDefault "background";
          units =
            map
              (name: {
                inherit name;
                provider = "nixos";
              })
              [
                "bazarr.service"
                "lidarr.service"
                "prowlarr.service"
                "radarr.service"
                "sonarr.service"
              ];
        };

        users = {
          groups = {
            prowlarr = { };
          };
          users = {
            bazarr.extraGroups = [ "media" ];
            prowlarr = {
              isSystemUser = true;
              group = "prowlarr";
              extraGroups = [ "media" ];
            };
            lidarr.extraGroups = [ "media" ];
            radarr.extraGroups = [ "media" ];
            sonarr.extraGroups = [ "media" ];
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
