{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      # Enable Steam with proper system support
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
      };

      # Required for gaming performance
      programs.gamemode.enable = true;
    };

  flake.modules.homeManager.gaming =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        mangohud
        gamescope
      ];
    };
}
