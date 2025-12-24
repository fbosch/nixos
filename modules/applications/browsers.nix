{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [ local.helium-browser ];

      xdg.mimeApps.defaultApplications = {
        "text/html" = [ "helium-browser.desktop" ];
        "x-scheme-handler/http" = [ "helium-browser.desktop" ];
        "x-scheme-handler/https" = [ "helium-browser.desktop" ];
        "x-scheme-handler/about" = [ "helium-browser.desktop" ];
        "x-scheme-handler/unknown" = [ "helium-browser.desktop" ];
      };
    };
}
