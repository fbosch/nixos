{ config, ... }:
{
  flake.modules.nixos."services/servarr" =
    { lib, ... }:
    {
      config = {
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
