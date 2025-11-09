{
  flake.modules.homeManager.applications = { pkgs, ... }:
    let
      defaultBrowser = "helium-browser.desktop";
    in
    {
      home.packages = with pkgs; [ local.helium-browser ];

      xdg.mimeApps.defaultApplications = {
        "text/html" = [ defaultBrowser ];
        "x-scheme-handler/http" = [ defaultBrowser ];
        "x-scheme-handler/https" = [ defaultBrowser ];
        "x-scheme-handler/about" = [ defaultBrowser ];
        "application/xhtml+xml" = [ defaultBrowser ];
        "application/x-extension-htm" = [ defaultBrowser ];
        "application/x-extension-html" = [ defaultBrowser ];
      };
    };
}
