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
        "org/nemo/compact-view".all-columns-have-same-width = false;

        "org/nemo/icon-view".labels-beside-icons = false;

        "org/nemo/list-view" = {
          default-column-order = [
            "name"
            "size"
            "type"
            "date_modified"
            "date_created_with_time"
            "date_accessed"
            "date_created"
            "detailed_type"
            "group"
            "where"
            "mime_type"
            "date_modified_with_time"
            "octal_permissions"
            "owner"
            "permissions"
          ];
          default-visible-columns = [
            "name"
            "size"
            "type"
            "date_modified"
            "date_created_with_time"
            "date_accessed"
          ];
          enable-folder-expansion = false;
        };

        "org/nemo/plugins".disabled-actions = [
          "set-resolution.nemo_action"
          "set-as-background.nemo_action"
          "change-background.nemo_action"
        ];

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
          always-use-browser = true;
          click-double-parent-folder = false;
          confirm-move-to-trash = true;
          date-font-choice = "system-mono";
          date-format = "informal";
          default-folder-viewer = "icon-view";
          default-sort-in-reverse-order = false;
          enable-delete = true;
          ignore-view-metadata = true;
          inherit-folder-viewer = false;
          inherit-show-thumbnails = true;
          mouse-use-extra-buttons = false;
          quick-renames-with-pause-in-between = true;
          show-computer-icon-toolbar = false;
          show-delete-permanently = true;
          show-edit-icon-toolbar = true;
          show-full-path-titles = true;
          show-hidden-files = true;
          show-home-icon-toolbar = true;
          show-image-thumbnails = "always";
          show-location-entry = true;
          show-new-folder-icon-toolbar = true;
          show-open-in-terminal-toolbar = false;
          show-reload-icon-toolbar = true;
          show-show-thumbnails-toolbar = false;
          show-toggle-extra-pane-toolbar = true;
          show-up-icon-toolbar = true;
          swap-trash-delete = false;
          tooltips-in-icon-view = true;
          tooltips-in-list-view = false;
          tooltips-on-desktop = true;
          tooltips-show-access-date = true;
          tooltips-show-birth-date = true;
          tooltips-show-file-type = true;
          tooltips-show-mod-date = true;
          tooltips-show-path = false;
        };
        "org/nemo/search" = {
          search-files-use-regex = true;
          search-reverse-sort = false;
          search-sort-column = "name";
        };
        "org/nemo/window-state" = {
          sidebar-bookmark-breakpoint = 4;
          start-with-sidebar = true;
        };
      };
    };
}
