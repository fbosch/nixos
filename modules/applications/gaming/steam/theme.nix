_: {
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
            ${lib.getExe pkgs.adwsteamgtk} -u
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
