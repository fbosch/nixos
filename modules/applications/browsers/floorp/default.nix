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
            "surge@surge-downloader.com" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/surge@surge-downloader.com/latest.xpi";
            };
            "{de22fd49-c9ab-4359-b722-b3febdc3a0b0}" = {
              installation_mode = "normal_installed";
              install_url = "https://addons.mozilla.org/firefox/downloads/latest/{de22fd49-c9ab-4359-b722-b3febdc3a0b0}/latest.xpi";
            };
          };
        };
      };
      floorpRelabelLauncher = pkgs.writeShellApplication {
        name = "floorp-wl-relabel";
        runtimeInputs = [
          pkgs.flatpak
          pkgs.local.wl-relabel
        ];
        text = ''
          exec wl-relabel -- flatpak run one.ablaze.floorp "$@"
        '';
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

      home.packages = [ floorpRelabelLauncher ];

      programs.wl-relabel.rules = ''
        # PiP must be identifiable before Hyprland predicts its initial size.
        [[rule]]
        app_id = ["one.ablaze.floorp"]
        when.title_contains = "Picture-in-Picture"
        then.app_id = "{app_id}-pip"
      '';

      xdg = {
        dataFile."flatpak/extension/one.ablaze.floorp.systemconfig/${flatpakArch}/stable/policies/policies.json".source =
          policies;

        desktopEntries."one.ablaze.floorp" = {
          name = "Floorp";
          genericName = "Web Browser";
          exec = "${lib.getExe floorpRelabelLauncher} %U";
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
