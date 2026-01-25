{ config, ... }:
{
  flake.modules.nixos."services/plex" =
    { config
    , lib
    , ...
    }:
    {
      config = lib.mkIf config.services.plex.enable {
        services.plex.openFirewall = lib.mkDefault true;
      };
    };
}
