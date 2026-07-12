{ inputs, config, ... }:
let
  inherit (config.flake.lib) lazyApp;
in
{
  # NixOS module: Steam-specific gaming configuration
  flake.modules.nixos.gaming =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        (lazyApp pkgs steamcmd)
        steam-run
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
          extraArgs = "-system-composer";
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

      home-manager.sharedModules = [
        inputs.steam-config-nix.homeModules.default
        ({ lib, osConfig, ... }: {
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
                  args = [ "--vulkan" ];
                };
              };
            };
          };
        })
      ];

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
            run ${applySteamTheme}
          '';
        }
      );

      dconf.settings = lib.mkIf osConfig.programs.steam.enable {
        "io/github/Foldex/AdwSteamGtk".prefs-install-custom-css = true;
      };

      # Custom CSS to match MonoThemeDark color scheme
      xdg.configFile."AdwSteamGtk/custom.css" = lib.mkIf osConfig.programs.steam.enable {
        source = ./custom.css;
      };
    };
}
