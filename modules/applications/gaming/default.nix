_: {
  # NixOS module: Generic gaming system configuration
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        mangohud
        steam-run
        wowup-cf
        protontricks
        wineWow64Packages.stable
        faugus-launcher
        vulkan-tools
        protonup-qt
        # sgdboop - disabled due to build error in nixpkgs (function signature mismatch)
        steamtinkerlaunch
        lact
        nvitop
      ];

      systemd.packages = with pkgs; [ lact ];
      systemd.services.lact.enable = true;

      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;

      programs = {
        gamescope = {
          enable = true;
          package = pkgs.gamescope.overrideAttrs (_: {
            NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
          });
        };

        # Required for gaming performance
        gamemode.enable = true;
      };
    };

  # Home Manager module: Generic gaming user applications
  flake.modules.homeManager.applications = {
    # Flatpak gaming applications
    services.flatpak.packages = [
      "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08" # Vulkan post-processing
      "org.freedesktop.Platform.VulkanLayer.MangoHud//25.08" # MangoHud overlay
      "io.mgba.mGBA" # GBA emulator
    ];

    xdg.desktopEntries.faugus-launcher = {
      name = "Faugus Launcher";
      exec = "gamemoderun env WINEFSYNC=1 WINEESYNC=1 DXVK_STATE_CACHE=1 faugus-launcher %U";
      icon = "faugus-launcher";
      type = "Application";
      categories = [ "Game" ];
      startupNotify = false;
      terminal = false;
    };
  };
}
