{
  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    {
      home.activation.floorpUserJs = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        FLOORP_PROFILE="$HOME/.var/app/one.ablaze.floorp/.floorp"
        if [ -d "$FLOORP_PROFILE" ]; then
          ${pkgs.findutils}/bin/find "$FLOORP_PROFILE" -maxdepth 1 -iname "*default*" -type d ! -name "static-*" | while IFS= read -r PROFILE_DIR; do
            ${pkgs.coreutils}/bin/install -m 0644 ${./user.js} "$PROFILE_DIR/user.js"
            echo "Floorp user.js installed at $PROFILE_DIR/user.js"
          done
        fi
      '';

      services.flatpak.packages = [
        "one.ablaze.floorp"
      ];

      xdg.desktopEntries."one.ablaze.floorp" = {
        name = "Floorp";
        genericName = "Web Browser";
        exec = "flatpak run one.ablaze.floorp %U";
        icon = "one.ablaze.floorp";
        type = "Application";
        categories = [
          "Network"
          "WebBrowser"
        ];
        mimeType = [
          "text/html"
          "text/xml"
          "application/xhtml+xml"
          "x-scheme-handler/http"
          "x-scheme-handler/https"
        ];
        startupNotify = true;
        terminal = false;
        settings = {
          StartupWMClass = "floorp";
          X-Flatpak = "one.ablaze.floorp";
        };
      };
    };
}
