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

        # Ananicy rules for Plex processes
        services.ananicy.customRules = [
          # Main Plex Media Server - highest priority for smooth playback/transcoding
          {
            name = "Plex Media Serv";
            type = "Player-Video";
            nice = -5;
            ioclass = "best-effort";
            ionice = 0;
          }
          # Plex Tuner Service - medium-high priority for live TV
          {
            name = "Plex Tuner Serv";
            type = "Player-Video";
            nice = -3;
          }
          # Plex Plugin Host - normal priority
          {
            name = "Plex Script Hos";
            nice = 0;
          }
        ];
      };
    };
}
