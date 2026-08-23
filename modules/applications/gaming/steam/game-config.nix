{
  flake.modules.nixos.gaming = {
    networking.firewall.allowedUDPPorts = [
      # Baldur's Gate 3 LAN lobby discovery and connections.
      23253
    ];
  };

  flake.modules.homeManager.applications =
    { lib, osConfig, ... }:
    lib.optionalAttrs osConfig.programs.steam.enable {
      programs.steam.config = {
        enable = true;
        onSteamRunning = "wait";

        apps = {
          # Noita
          "881100" = {
            wrappers = [ "gamemoderun" ];
          };

          # Baldur's Gate 3
          "1086940" = {
            wrappers = [ "gamemoderun" ];
            args = [ "--vulkan --skip-launcher" ];
          };
        };
      };
    };
}
