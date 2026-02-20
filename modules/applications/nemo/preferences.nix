{
  flake.modules.homeManager.applications =
    _:
    {
      dconf.settings = {
        "org/nemo/sidebar-panels/tree" = {
          sync-bookmarks = true;
        };
        "org/cinnamon/desktop/applications/terminal" = {
          exec = "wezterm";
        };
        "org/nemo/preferences" = {
          enable-delete = true;
          show-delete-permanently = true;
          show-location-entry = true;
          mouse-use-extra-buttons = false;
          show-image-thumbnails = "always";
          default-folder-viewer = "list-view";
          show-hidden-files = true;
          show-full-path-titles = true;
          quick-renames-with-pause-in-between = true;
        };
        "org/nemo/window-state" = {
          start-with-sidebar = true;
        };
      };
    };
}
