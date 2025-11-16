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
              ] ++ lib.optional (args ? class) "--class=${args.class}";
              hardenedFlags = lib.lists.unique (defaultFlags ++ extraFlags);
              policyBase = {
                ExtensionInstallBlocklist = [ "*" ];
                PasswordManagerEnabled = false;
                AutofillAddressEnabled = false;
                AutofillCreditCardEnabled = false;
                BackgroundModeEnabled = false;
                SafeBrowsingProtectionLevel = 2;
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
