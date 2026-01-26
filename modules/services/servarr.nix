{ config, ... }:
{
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
        users = {
          groups.media = { };
          users = {
            bazarr.extraGroups = [
              "media"
              "users"
            ];
            jackett.extraGroups = [
              "media"
              "users"
            ];
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

          jackett = {
            enable = true;
            openFirewall = lib.mkDefault true;
          };
        };
      };
    };
}
