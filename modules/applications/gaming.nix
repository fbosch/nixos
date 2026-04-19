_: {
  # NixOS module: Steam and gaming system configuration
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
        nvitop
      ];

      hardware.graphics.enable = true;
      hardware.graphics.enable32Bit = true;

      programs = {
        gamescope = {
          enable = true;
          package = pkgs.gamescope.overrideAttrs (_: {
            NIX_CFLAGS_COMPILE = [ "-fno-fast-math" ];
          });
        };

        # Enable Steam with proper system support
        steam = {
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
            extraEnv = {
              DXVK_ASYNC = "1";
              PROTON_HIDE_NVIDIA_GPU = "0";
              PROTON_ENABLE_NVAPI = "1";
              GAMEMODERUN = "1";
              PROTON_LOCAL_SHADER_CACHE = "1";
              TZ = ":/etc/localtime";
              TZDIR = "/etc/zoneinfo";
            };
          };
        };

        # Required for gaming performance
        gamemode.enable = true;
      };
    };

  # Home Manager module: Apply Adwaita theme to Steam
  flake.modules.homeManager.applications =
    { pkgs
    , lib
    , config
    , osConfig
    , ...
    }:
    {
      home.packages = lib.mkIf osConfig.programs.steam.enable [ pkgs.adwsteamgtk ];

      # Flatpak gaming applications
      services.flatpak.packages = [
        "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08" # Vulkan post-processing
        "org.freedesktop.Platform.VulkanLayer.MangoHud//25.08" # MangoHud overlay
        "io.mgba.mGBA" # GBA emulator
      ];

      home.activation = lib.mkIf osConfig.programs.steam.enable (
        let
          applySteamTheme = pkgs.writeShellScript "applySteamTheme" ''
            # This file gets copied with read-only permission from the nix store
            # if it is present, it causes an error when the theme is applied. Delete it.
            custom="$HOME/.cache/AdwSteamInstaller/extracted/custom/custom.css"
            if [[ -f "$custom" ]]; then
              rm -f "$custom"
            fi
            ${lib.getExe pkgs.adwsteamgtk} -i
          '';
        in
        {
          updateSteamTheme = config.lib.dag.entryAfter [ "writeBoundary" "dconfSettings" ] ''
            if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ]; then
              echo "Home Manager generation unchanged, skipping Steam theme update"
              exit 0
            fi

            run ${applySteamTheme}
          '';
        }
      );

      dconf.settings = lib.mkIf osConfig.programs.steam.enable {
        "io/github/Foldex/AdwSteamGtk".prefs-install-custom-css = true;
      };

      # Custom CSS to match MonoThemeDark color scheme
      xdg.configFile."AdwSteamGtk/custom.css" = lib.mkIf osConfig.programs.steam.enable {
        source = ../../assets/steam-theme/custom.css;
      };

      # xdg.desktopEntries.steam =
      #   lib.mkIf (osConfig.programs.steam.enable && osConfig.services.mullvad-vpn.enable)
      #     {
      #       name = "Steam";
      #       comment = "Application for managing and playing games on Steam";
      #       exec = "${lib.getExe' pkgs.mullvad-vpn "mullvad-exclude"} steam steam://open/main %U";
      #       icon = "steam";
      #       type = "Application";
      #       categories = [
      #         "Network"
      #         "FileTransfer"
      #         "Game"
      #       ];
      #       mimeType = [
      #         "x-scheme-handler/steam"
      #         "x-scheme-handler/steamlink"
      #       ];
      #       terminal = false;
      #       settings = {
      #         PrefersNonDefaultGPU = "true";
      #         X-KDE-RunOnDiscreteGpu = "true";
      #       };
      #     };

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
