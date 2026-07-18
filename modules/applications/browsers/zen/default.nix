{
  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    {
      home.activation.zenProfileSetup = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ZEN_PROFILE="$HOME/.var/app/app.zen_browser.zen/.zen"
        if [ -d "$ZEN_PROFILE" ]; then
          ${pkgs.findutils}/bin/find "$ZEN_PROFILE" -maxdepth 1 -iname "*default*" -type d ! -name "static-*" | while IFS= read -r PROFILE_DIR; do
            ${pkgs.coreutils}/bin/install -m 0644 ${./user.js} "$PROFILE_DIR/user.js"
            echo "Zen user.js installed at $PROFILE_DIR/user.js"

            ${pkgs.coreutils}/bin/install -D -m 0644 ${./userContent.css} "$PROFILE_DIR/chrome/userContent.css"
            echo "Zen userContent.css installed at $PROFILE_DIR/chrome/userContent.css"

          done
        fi
      '';

      services.flatpak.packages = [
        "app.zen_browser.zen"
      ];

      systemd.user.services.zen-prewarm = {
        Unit = {
          Description = "Prewarm Zen Browser files into page cache";
          After = [ "default.target" ];
          StartLimitIntervalSec = 0;
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.writeShellScript "zen-prewarm" ''
            set -euo pipefail

            targets=()
            zen_app_roots=(
              "$HOME/.local/share/flatpak/app/app.zen_browser.zen"
              "/var/lib/flatpak/app/app.zen_browser.zen"
            )
            zen_cache="$HOME/.var/app/app.zen_browser.zen/cache"
            zen_profile_root="$HOME/.var/app/app.zen_browser.zen/.zen"

            for zen_app_root in "''${zen_app_roots[@]}"; do
              if [ -d "$zen_app_root" ]; then
                while IFS= read -r -d "" path; do
                  targets+=("$path")
                done < <(${pkgs.findutils}/bin/find "$zen_app_root" -path "*/files/zen" -type d -print0)
              fi
            done

            if [ -d "$zen_cache" ]; then
              targets+=("$zen_cache")
            fi

            if [ -d "$zen_profile_root" ]; then
              while IFS= read -r -d "" profile_dir; do
                profile_targets=(
                  "$profile_dir/addons.json"
                  "$profile_dir/compatibility.ini"
                  "$profile_dir/content-prefs.sqlite"
                  "$profile_dir/cookies.sqlite"
                  "$profile_dir/extension-preferences.json"
                  "$profile_dir/extensions.json"
                  "$profile_dir/favicons.sqlite"
                  "$profile_dir/handlers.json"
                  "$profile_dir/permissions.sqlite"
                  "$profile_dir/places.sqlite"
                  "$profile_dir/prefs.js"
                  "$profile_dir/search.json.mozlz4"
                  "$profile_dir/sessionCheckpoints.json"
                  "$profile_dir/user.js"
                )

                for profile_target in "''${profile_targets[@]}"; do
                  if [ -e "$profile_target" ]; then
                    targets+=("$profile_target")
                  fi
                done

                for profile_target in browser-extension-data crashes datareporting extensions security_state sessionstore-backups startupCache storage; do
                  if [ -e "$profile_dir/$profile_target" ]; then
                    targets+=("$profile_dir/$profile_target")
                  fi
                done
              done < <(${pkgs.findutils}/bin/find "$zen_profile_root" -maxdepth 1 -iname "*default*" -type d ! -name "static-*" -print0)
            fi

            if [ "''${#targets[@]}" -gt 0 ]; then
              ${pkgs.util-linux}/bin/ionice -c 3 ${pkgs.coreutils}/bin/nice -n 19 ${pkgs.vmtouch}/bin/vmtouch -q -t "''${targets[@]}"
            fi
          ''}";
        };

        Install.WantedBy = [ "default.target" ];
      };

      services.flatpak.overrides."app.zen_browser.zen" = {
        Context = {
          sockets = [
            "wayland"
            "fallback-x11"
            "pulseaudio"
            "cups"
          ];
          shared = [
            "network"
            "ipc"
          ];
          devices = [ "dri" ];
        };
        Environment = {
          LIBVA_DRIVER_NAME = "nvidia";
          MOZ_DISABLE_RDD_SANDBOX = "1";
          MOZ_ENABLE_WAYLAND = "1";
          MOZ_USE_XINPUT2 = "1";
          GDK_BACKEND = "wayland";
          TZ = "Europe/Copenhagen";
        };
      };

      xdg.desktopEntries."app.zen_browser.zen" = {
        name = "Zen Browser";
        exec = "mullvad-exclude flatpak run app.zen_browser.zen %U";
        icon = "app.zen_browser.zen";
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
          "application/x-xpinstall"
          "application/pdf"
          "application/json"
        ];
        startupNotify = false;
        terminal = false;
        settings = {
          StartupWMClass = "zen";
          X-MultipleArgs = "false";
          Keywords = "Internet;WWW;Browser;Web;Explorer;";
          X-Flatpak = "app.zen_browser.zen";
          PrefersNonDefaultGPU = "true";
        };
      };
    };
}
