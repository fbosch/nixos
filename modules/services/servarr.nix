{ config, ... }:
{
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
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
