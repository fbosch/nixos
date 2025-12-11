_:

{
  flake.overlays.chromium-webapps-hardening = final: prev:
    let
      inherit (prev) lib;
      hasChromiumLib = lib.hasAttrByPath [ "nix-webapps-lib" "mkChromiumApp" ] prev;
    in
    if !hasChromiumLib then { }
    else
      let
        oldMkChromiumApp = prev.nix-webapps-lib.mkChromiumApp;
        mkHardenedChromiumApp = args:
          let
            hardening = args.hardening or { };
            enabled = hardening.enabled or true;
            sanitizedArgs = builtins.removeAttrs args [ "hardening" ];
            baseDrv = oldMkChromiumApp sanitizedArgs;
          in
          if !enabled then baseDrv
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
                # Better desktop integration
                "--disable-features=VizDisplayCompositor"
              ] ++ lib.optional (args ? class) "--class=${args.class}";
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
              flagArgs = lib.concatMapStringsSep " " (flag: ''--add-flags ${lib.escapeShellArg flag}'') hardenedFlags;
            in
            baseDrv.overrideAttrs (_finalAttrs: prevAttrs:
              let
                basePostInstall = prevAttrs.postInstall or "";
                wrapCommand = ''wrapProgram "$out/bin/${args.appName}" --set CHROME_POLICY_FILES_DIR "$out/share/chromium/policies"''
                  + lib.optionalString (hardenedFlags != [ ]) " ${flagArgs}";
              in
              {
                nativeBuildInputs = lib.lists.unique ((prevAttrs.nativeBuildInputs or [ ]) ++ [ final.makeWrapper ]);
                postInstall = ''
                  ${basePostInstall}
                  install -Dm644 ${policyFile} "$out/share/chromium/policies/managed/${args.appName}.json"
                  ${wrapCommand}
                '';
                passthru = (prevAttrs.passthru or { }) // {
                  hardenedChromium = {
                    inherit policyFile;
                    flags = hardenedFlags;
                  };
                };
              }
            );
      in
      {
        nix-webapps-lib = prev.nix-webapps-lib // {
          mkChromiumApp = mkHardenedChromiumApp;
        };
      };
}
