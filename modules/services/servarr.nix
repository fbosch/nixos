{ config, ... }:
{
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
        users.groups.media = { };
        users.users.bazarr.extraGroups = [
          "media"
          "users"
        ];
        users.users.jackett.extraGroups = [
          "media"
          "users"
        ];
        users.users.lidarr.extraGroups = [
          "media"
          "users"
        ];
        users.users.radarr.extraGroups = [
          "media"
          "users"
        ];
        users.users.sonarr.extraGroups = [
          "media"
          "users"
        ];

        services.lidarr = {
          enable = true;
          openFirewall = lib.mkDefault true;
        };

        services.sonarr = {
          enable = true;
          openFirewall = lib.mkDefault true;
        };

        services.radarr = {
          enable = true;
          openFirewall = lib.mkDefault true;
        };

        services.bazarr = {
          enable = true;
          openFirewall = lib.mkDefault true;
        };

        services.jackett = {
          enable = true;
          openFirewall = lib.mkDefault true;
        };
      };
    };
}
