{
  flake.modules.homeManager.applications =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      flatpakArch = lib.head (lib.splitString "-" pkgs.stdenv.hostPlatform.system);
      policies = (pkgs.formats.json { }).generate "floorp-policies.json" {
        policies = {
          DisableAppUpdate = true;
          DontCheckDefaultBrowser = true;
          ExtensionSettings = {
            "ATBC@EasonWong" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/ATBC@EasonWong/latest.xpi";
            };
            "switchyomega@feliscatus.addons.mozilla.org" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/switchyomega@feliscatus.addons.mozilla.org/latest.xpi";
            };
            "uBlock0@raymondhill.net" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/uBlock0@raymondhill.net/latest.xpi";
            };
            "{84601290-bec9-494a-b11c-1baa897a9683}" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/{84601290-bec9-494a-b11c-1baa897a9683}/latest.xpi";
            };
            "jid1-KdTtiCj6wxVAFA@jetpack" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/jid1-KdTtiCj6wxVAFA@jetpack/latest.xpi";
            };
          };
        };
      };
    in
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

      xdg = {
        dataFile."flatpak/extension/one.ablaze.floorp.systemconfig/${flatpakArch}/stable/policies/policies.json".source =
          policies;

        desktopEntries."one.ablaze.floorp" = {
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
    };
}
