{
  flake.modules.homeManager.applications =
    { pkgs
    , ...
    }:
    {
      home.packages = with pkgs; [ local.helium-browser ];

      xdg.mimeApps.defaultApplications = {
        "text/html" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/http" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/https" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/about" = [ "io.github.zen_browser.zen.desktop" ];
        "x-scheme-handler/unknown" = [ "io.github.zen_browser.zen.desktop" ];
      };
    };
}
