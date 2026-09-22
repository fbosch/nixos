{ inputs, ... }:
{
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        steamcmd
        steamtinkerlaunch
      ];

      # Enable Steam with proper system support
      programs.steam = {
        enable = true;
        gamescopeSession.enable = true;
        remotePlay.openFirewall = true;
        dedicatedServer.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;
        extraPackages = with pkgs; [
          kdePackages.breeze
        ];
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
        package = pkgs.steam.override {
          extraArgs = "-system-composer --enable-features=UseOzonePlatform --ozone-platform=wayland";
          extraEnv = {
            DXVK_HUD = "0";
            GAMEMODERUN = "1";
            PROTON_HIDE_NVIDIA_GPU = "0";
            PROTON_ENABLE_NVAPI = "1";
            PROTON_USE_NTSYNC = "1";
            PROTON_LOCAL_SHADER_CACHE = "1";
            PROTON_DXVK_LOWLATENCY = "1";
            TZ = ":/etc/localtime";
            TZDIR = "/etc/zoneinfo";
          };
        };
      };

      home-manager.sharedModules = [
        inputs.steam-config-nix.homeModules.default
      ];

    };

  flake.modules.homeManager.gaming = {
    systemd.user.services.steam-config-patcher.Unit.ConditionPathIsDirectory =
      "%h/.local/share/Steam/userdata";
  };
}
