{ config, ... }:
{
  flake.modules.nixos."services/plex" =
    { config
    , lib
    , ...
    }:
    let
      cfg = config.services.plex;
    in
    {
      options.services.plex = {
        transcodeInRAM = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Store Plex transcoding cache in RAM (tmpfs) for better performance.
            Recommended for systems with sufficient RAM (8GB+).
            Reduces disk wear and significantly speeds up transcoding.
          '';
        };

        transcodeRAMSize = lib.mkOption {
          type = lib.types.str;
          default = "4G";
          example = "8G";
          description = ''
            Size of tmpfs for transcode cache when transcodeInRAM is enabled.

            Recommended sizes:
            - 2G: Systems with 8GB RAM (1 concurrent 1080p stream)
            - 4G: Systems with 16GB RAM (2 concurrent 1080p streams)
            - 8G: Systems with 32GB+ RAM (4K transcoding or 4+ streams)

            Note: tmpfs grows on-demand and only uses RAM when actively transcoding.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        services.plex.openFirewall = lib.mkDefault true;

        # Plex transcoding in RAM for faster performance and less disk wear
        fileSystems."/var/lib/plex/Plex Media Server/Cache/Transcode" = lib.mkIf cfg.transcodeInRAM {
          device = "tmpfs";
          fsType = "tmpfs";
          options = [
            "defaults"
            "size=${cfg.transcodeRAMSize}"
            "mode=0755"
            "uid=plex"
            "gid=plex"
          ];
        };

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
