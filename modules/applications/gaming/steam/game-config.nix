_:
{
  flake.modules.nixos.gaming = {
    networking.firewall.allowedUDPPorts = [
      # Baldur's Gate 3 LAN lobby discovery and connections.
      23253
    ];
  };

  flake.modules.homeManager.applications =
    { lib, osConfig, ... }:
    {
      programs.steam.config = lib.mkIf osConfig.programs.steam.enable {
        enable = true;
        onSteamRunning = "wait";

        apps = {
          Noita = {
            id = 881100;
            launchOptions.wrappers = [ "gamemoderun" ];
          };

          "Baldur's Gate 3" = {
            id = 1086940;
            launchOptions = {
              wrappers = [ "gamemoderun" ];
              args = [ "--vulkan --skip-launcher" ];
            };
          };
        };
      };
    };
}
