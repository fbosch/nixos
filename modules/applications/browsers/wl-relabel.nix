{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = [ pkgs.local.wl-relabel ];

    xdg.configFile."wl-relabel/rules.toml".text = ''
      # Undocked Chromium DevTools otherwise satisfies the popup conditions.
      [[rule]]
      app_id = ["helium"]
      when.decorations = "server_side"
      when.title_contains = "DevTools"
      then.app_id = "helium-devtools"

      [[rule]]
      app_id = ["helium"]
      when.decorations = "server_side"
      when.min_width_below = 400
      then.app_id = "helium-popup"

      [[rule]]
      app_id = ["app.zen_browser.zen"]
      when.decorations = "server_side"
      when.min_width_below = 400
      then.app_id = "{app_id}-popup"
    '';
  };
}
