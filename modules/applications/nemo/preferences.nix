{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
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
      dconf.settings = {
        "org/nemo/sidebar-panels/tree" = {
          sync-bookmarks = true;
        };
        "org/cinnamon/desktop/applications/terminal" = {
          exec = "${weztermForNemo}/bin/nemo-wezterm";
          exec-arg = "--";
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
          start-with-sidebar = true;
        };
      };
    };
}
