{ config, ... }:
{
  flake.modules.nixos."system/ananicy" =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      options.services.ananicy.customRules = lib.mkOption {
        type = with lib.types; listOf attrs;
        default = [ ];
        example = [
          {
            name = "Plex Media Server";
            type = "Media";
            nice = -5;
            ioclass = "realtime";
          }
          {
            name = "Radarr";
            type = "BG_CPUIO";
            nice = 10;
            ioclass = "idle";
          }
        ];
        description = "Custom ananicy rules for specific services";
      };

      config = lib.mkIf config.services.ananicy.enable {
        services.ananicy = {
          # Use ananicy-cpp for better performance (C++ rewrite of original ananicy)
          package = pkgs.ananicy-cpp;

          # Use CachyOS rules - comprehensive ruleset for servers and desktops
          # Includes rules for common services, databases, media servers, etc.
          rulesProvider = pkgs.ananicy-rules-cachyos;

          # Merge custom rules with extraRules
          extraRules = config.services.ananicy.customRules;
        };
      };
    };
}
