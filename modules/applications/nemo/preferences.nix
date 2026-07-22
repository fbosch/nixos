{
  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    let
      weztermForNemo = pkgs.writeShellApplication {
        name = "nemo-wezterm";
        runtimeInputs = [ pkgs.wezterm ];
        text = ''
          if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
            shift
          fi

          exec wezterm start --cwd "$PWD" "$@"
        '';
      };
    in
    {
      xdg.configFile."gtk-3.0/bookmarks".text = ''
        file://${config.xdg.userDirs.download} Downloads
        file://${config.xdg.userDirs.pictures} Pictures
        file:///mnt/games Games
        file://${config.xdg.userDirs.projects} Projects
      '';

      dconf.settings = {
        "org/nemo/sidebar-panels/tree" = {
          sync-bookmarks = true;
        };
        "org/cinnamon/desktop/applications/terminal" = {
          exec = "${weztermForNemo}/bin/nemo-wezterm";
          exec-arg = "--";
        };
        "org/freedesktop/tracker/miner/files" = {
          index-recursive-directories = [
            "&DESKTOP"
            "&DOCUMENTS"
            "&MUSIC"
            "&PICTURES"
            "&VIDEOS"
            "$HOME/Projects"
          ];
          index-single-directories = [
            "$HOME"
            "&DOWNLOAD"
          ];
        };
        "org/nemo/preferences" = {
          enable-delete = true;
          show-delete-permanently = true;
          show-location-entry = true;
          mouse-use-extra-buttons = false;
          show-image-thumbnails = "always";
          default-folder-viewer = "icon-view";
          show-hidden-files = true;
          show-full-path-titles = true;
          quick-renames-with-pause-in-between = true;
        };
        "org/nemo/window-state" = {
          sidebar-bookmark-breakpoint = 4;
          start-with-sidebar = true;
        };
      };
    };
}
