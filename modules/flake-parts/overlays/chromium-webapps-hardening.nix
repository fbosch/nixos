_:

{
  flake.overlays.chromium-webapps-hardening =
    final: prev:
    let
      inherit (prev) lib;
      hasChromiumLib = lib.hasAttrByPath [ "nix-webapps-lib" "mkChromiumApp" ] prev;
    in
    if !hasChromiumLib then
      { }
    else
      let
        oldMkChromiumApp = prev.nix-webapps-lib.mkChromiumApp;
        mkHardenedChromiumApp =
          args:
          let
            hardening = args.hardening or { };
            enabled = hardening.enabled or true;
            sanitizedArgs = builtins.removeAttrs args [ "hardening" ];
            baseDrv = oldMkChromiumApp sanitizedArgs;
          in
          if !enabled then
            baseDrv
          else
            let
              extraFlags = hardening.extraFlags or [ ];
              defaultFlags = [
                "--disable-extensions"
                "--disable-sync"
                "--disable-background-networking"
                "--no-first-run"
                "--no-default-browser-check"
                "--site-per-process"
                "--isolate-origins=${args.url}"
                "--disable-features=TranslateUI"
                # Disable crash reporter to avoid crashpad issues on NixOS
                "--disable-crash-reporter"
                # Performance improvements
                "--enable-gpu-rasterization"
                "--enable-zero-copy"
                "--disable-background-timer-throttling"
                "--disable-renderer-backgrounding"
                "--disable-backgrounding-occluded-windows"
                "--max-tiles-for-interest-area=512"
                "--num-raster-threads=4"
                "--enable-hardware-overlays=single-fullscreen,single-on-top,underlay"
                "--use-gl=desktop"
                # Additional password manager disabling
                "--disable-password-generation"
                "--disable-password-saving"
                "--disable-password-manager-reauthentication"
                "--disable-save-password-bubble"
                # Memory and performance optimizations
                "--disable-low-end-device-mode"
                "--enable-threaded-compositing"
                "--memory-pressure-off"
                "--max-tiles-for-interest-area=512"
                "--enable-overlay-scrollbar"
                "--disable-component-extensions-with-background-pages"
                "--disable-hang-monitor"
                "--disable-ipc-flooding-protection"
                "--disable-popup-blocking"
                "--disable-prompt-on-repost"
                # Additional UX improvements
                "--disable-infobars"
                "--disable-session-crashed-bubble"
                "--disable-component-update"
                # Better desktop integration and performance
                "--enable-features=VizDisplayCompositor"
              ]
              ++ lib.optional (args ? class) "--class=${args.class}";
              hardenedFlags = lib.lists.unique (defaultFlags ++ extraFlags);
              policyBase = {
                ExtensionInstallBlocklist = [ "*" ];
                PasswordManagerEnabled = false;
                PasswordLeakDetectionEnabled = false;
                PasswordProtectionWarningTrigger = 0;
                PasswordManagerAllowShowPasswordBubbles = false;
                PasswordManagerAllowShowPasswordSuggestions = false;
                AutofillAddressEnabled = false;
                AutofillCreditCardEnabled = false;
                BackgroundModeEnabled = false;
                SafeBrowsingProtectionLevel = 2;
                # Core security policies (always applied)
                EnableMediaRouter = false;
                TranslateEnabled = false;
                PrintPreviewDisabled = false;
                # Hardware acceleration enabled by default (can be overridden)
                HardwareAccelerationModeEnabled = true;
                # Default content policies (can be overridden per app)
                DefaultCookiesSetting = 1; # Allow cookies
                DefaultImagesSetting = 1; # Allow images
                DefaultJavaScriptSetting = 1; # Allow JavaScript
                DefaultPluginsSetting = 2; # Block plugins
                # Restrictive defaults for privacy (apps can override if needed)
                DefaultPopupsSetting = 2; # Block popups
                DefaultNotificationsSetting = 2; # Block notifications
                DefaultGeolocationSetting = 2; # Block geolocation
                DefaultMediaStreamSetting = 2; # Block media stream
              };
              policyOverrides = hardening.policyOverrides or { };
              policy = lib.recursiveUpdate policyBase policyOverrides;
              policyFile = final.writeText "${args.appName}-managed-policy.json" (builtins.toJSON policy);
              flagArgs = lib.concatMapStringsSep " "
                (
                  flag: "--add-flags ${lib.escapeShellArg flag}"
                )
                hardenedFlags;
            in
            baseDrv.overrideAttrs (
              _finalAttrs: prevAttrs:
              let
                basePostInstall = prevAttrs.postInstall or "";
                wrapCommand =
                  ''wrapProgram "$out/bin/${args.appName}" --set CHROME_POLICY_FILES_DIR "$out/share/chromium/policies" --set BREAKPAD_DUMP_LOCATION "/tmp"''
                  + lib.optionalString (hardenedFlags != [ ]) " ${flagArgs}";
              in
              {
                nativeBuildInputs = lib.lists.unique (
                  (prevAttrs.nativeBuildInputs or [ ])
                  ++ [
                    final.makeWrapper
                    final.librsvg
                  ]
                );
                buildInputs = lib.lists.unique ((prevAttrs.buildInputs or [ ]) ++ [ final.hicolor-icon-theme ]);
                postInstall = ''
                  ${basePostInstall}
                  install -Dm644 ${policyFile} "$out/share/chromium/policies/managed/${args.appName}.json"
                  ${wrapCommand}

                  # Install hicolor icon theme index for proper icon discovery
                  mkdir -p "$out/share/icons/hicolor"
                  ln -sf "${final.hicolor-icon-theme}/share/icons/hicolor/index.theme" "$out/share/icons/hicolor/index.theme"
                '';
                postFixup = ''
                  # Improve desktop file and icon locations for better Waybar recognition
                  # This runs after the desktop file is copied
                  desktop_file="$out/share/applications/${args.appName}.desktop"

                  if [ -f "$desktop_file" ]; then
                    # Install icon to standard FreeDesktop locations
                    mkdir -p "$out/share/icons/hicolor/512x512/apps"
                    original_icon=$(${final.gnugrep}/bin/grep "^Icon=" "$desktop_file" | ${final.coreutils}/bin/cut -d'=' -f2)

                    if [ -f "$original_icon" ]; then
                      # Chromium's --app flag generates class names like: chrome-domain.tld__-ProfileName
                      # Extract domain from URL to build the actual class name
                      domain=$(echo "${args.url}" | ${final.gnused}/bin/sed -E 's|^https?://([^/]+).*|\1|')
                      chromium_class="chrome-''${domain}__-${args.profile}"
                      
                      # Convert SVG to PNG for better GTK/Waybar compatibility
                      # Always use PNG for the final icon to ensure consistent rendering
                      icon_path="$out/share/icons/hicolor/512x512/apps/$chromium_class.png"
                      
                      if [[ "$original_icon" == *.svg ]]; then
                        # Convert SVG to PNG at 512x512
                        ${final.librsvg}/bin/rsvg-convert -w 512 -h 512 "$original_icon" -o "$icon_path"
                      else
                        # Copy PNG directly
                        ${final.coreutils}/bin/cp "$original_icon" "$icon_path"
                      fi
                      
                      # Also create a friendly-named symlink for manual use
                      ln -sf "$chromium_class.png" "$out/share/icons/hicolor/512x512/apps/${args.class}.png"
                      
                      # Use absolute path in desktop file for reliable icon lookup
                      # GTK supports absolute paths and Waybar's IconLoader will find them directly
                      ${final.gnused}/bin/sed -i "s|Icon=.*|Icon=$icon_path|" "$desktop_file"
                      
                      # Update StartupWMClass to match Chromium's actual behavior
                      ${final.gnused}/bin/sed -i '/^StartupWMClass=/d' "$desktop_file"
                      echo "StartupWMClass=$chromium_class" >> "$desktop_file"
                    fi
                    
                    # Add metadata
                    echo "Keywords=${args.desktopName or args.appName};webapp;chromium;" >> "$desktop_file"
                    echo "X-GNOME-UsesNotifications=true" >> "$desktop_file"
                    echo "X-KDE-StartupNotify=true" >> "$desktop_file"
                  fi
                '';
                passthru = lib.recursiveUpdate (prevAttrs.passthru or { }) {
                  hardenedChromium = {
                    inherit policyFile;
                    flags = hardenedFlags;
                  };
                };
              }
            );
      in
      {
        nix-webapps-lib = lib.recursiveUpdate prev.nix-webapps-lib {
          mkChromiumApp = mkHardenedChromiumApp;
        };
      };
}
