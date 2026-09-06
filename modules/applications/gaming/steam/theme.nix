{
  flake.modules.homeManager.applications =
    { pkgs
    , lib
    , osConfig
    , ...
    }:
    let
      applySteamTheme = pkgs.writeShellApplication {
        name = "apply-steam-theme";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          cache_marker="''${XDG_CACHE_HOME:-$HOME/.cache}/home-manager/adwsteamgtk-input"
          cache_input=${lib.escapeShellArg "${pkgs.adwsteamgtk}:${./custom.css}"}

          if [ -r "$cache_marker" ] && [ "$(<"$cache_marker")" = "$cache_input" ]; then
            echo "Steam theme inputs unchanged, skipping update"
            exit 0
          fi

          # The installer cannot replace this read-only file when copied from the Nix store.
          rm -f "$HOME/.cache/AdwSteamInstaller/extracted/custom/custom.css"
          ${lib.getExe pkgs.adwsteamgtk} -u

          mkdir -p "$(dirname "$cache_marker")"
          printf '%s\n' "$cache_input" > "$cache_marker"
        '';
      };
    in
    {
      home.packages = lib.mkIf osConfig.programs.steam.enable [ pkgs.adwsteamgtk ];

      systemd.user.services.adwsteamgtk-update = lib.mkIf osConfig.programs.steam.enable {
        Unit = {
          Description = "Update the Adwaita Steam theme";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe applySteamTheme;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      dconf.settings = lib.mkIf osConfig.programs.steam.enable {
        "io/github/Foldex/AdwSteamGtk".prefs-install-custom-css = true;
      };

      # Custom CSS to match MonoThemeDark color scheme
      xdg.configFile."AdwSteamGtk/custom.css" = lib.mkIf osConfig.programs.steam.enable {
        source = ./custom.css;
      };
    };
}
