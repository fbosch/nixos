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
        # sgdboop - disabled due to build error in nixpkgs (function signature mismatch)
        steamtinkerlaunch
      ];

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
    lib.optionalAttrs osConfig.programs.steam.enable {
      home.packages = [ pkgs.adwsteamgtk ];

      # Flatpak gaming applications
      # Note: Flatpak overrides are centralized in flatpak.nix
      services.flatpak.packages = [
        #  "net.lutris.Lutris" # Game launcher
        "net.davidotek.pupgui2" # ProtonUp-Qt for managing Proton versions
        "io.github.Faugus.faugus-launcher" # Game launcher
        "org.freedesktop.Platform.VulkanLayer.vkBasalt//25.08" # Vulkan post-processing
      ];

      home.activation =
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
            run ${applySteamTheme}
          '';
        };

      dconf.settings."io/github/Foldex/AdwSteamGtk".prefs-install-custom-css = true;

      # Custom CSS to match MonoThemeDark color scheme
      xdg.configFile."AdwSteamGtk/custom.css".source = ../../assets/steam-theme/custom.css;

      xdg.desktopEntries.steam = lib.mkIf osConfig.services.mullvad-vpn.enable {
        name = "Steam";
        comment = "Application for managing and playing games on Steam";
        exec = "${lib.getExe' pkgs.mullvad-vpn "mullvad-exclude"} steam %U";
        icon = "steam";
        type = "Application";
        categories = [
          "Network"
          "FileTransfer"
          "Game"
        ];
        mimeType = [
          "x-scheme-handler/steam"
          "x-scheme-handler/steamlink"
        ];
        terminal = false;
        settings = {
          PrefersNonDefaultGPU = "true";
          X-KDE-RunOnDiscreteGpu = "true";
        };
      };
    };
}
