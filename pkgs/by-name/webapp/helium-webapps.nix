{ pkgs }:

let
  inherit (pkgs) lib;

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
    EnableMediaRouter = false;
    TranslateEnabled = false;
    PrintPreviewDisabled = false;
    HardwareAccelerationModeEnabled = true;
    DefaultCookiesSetting = 1;
    DefaultImagesSetting = 1;
    DefaultJavaScriptSetting = 1;
    DefaultPluginsSetting = 2;
    DefaultPopupsSetting = 2;
    DefaultNotificationsSetting = 2;
    DefaultGeolocationSetting = 2;
    DefaultMediaStreamSetting = 2;
  };

  defaultFlags = [
    "--disable-extensions"
    "--disable-sync"
    "--disable-background-networking"
    "--no-first-run"
    "--no-default-browser-check"
    "--disable-crash-reporter"
    "--enable-gpu-rasterization"
    "--enable-zero-copy"
    "--enable-hardware-overlays=single-fullscreen,single-on-top,underlay"
    "--disable-password-generation"
    "--disable-password-saving"
    "--disable-password-manager-reauthentication"
    "--disable-low-end-device-mode"
    "--enable-overlay-scrollbar"
    "--disable-component-extensions-with-background-pages"
    "--disable-hang-monitor"
    "--disable-ipc-flooding-protection"
    "--disable-popup-blocking"
    "--disable-prompt-on-repost"
    "--disable-session-crashed-bubble"
    "--disable-component-update"
  ];

  hostForUrl =
    url:
    let
      match = builtins.match "^[a-zA-Z][a-zA-Z0-9+.-]*://([^/:?#]+).*" url;
    in
    if match == null then
      throw "mkHeliumApp: cannot infer favicon domain from URL ${url}"
    else
      builtins.head match;

  baseDomainFor =
    url:
    let
      labels = lib.splitString "." (hostForUrl url);
      labelCount = builtins.length labels;
    in
    if labelCount >= 2 then
      "${builtins.elemAt labels (labelCount - 2)}.${builtins.elemAt labels (labelCount - 1)}"
    else
      hostForUrl url;

  iconExtensionFor = icon: if lib.hasSuffix ".svg" (toString icon) then "svg" else "png";
  iconDirectoryFor = extension: if extension == "svg" then "scalable" else "512x512";
in
{
  mkHeliumApp =
    { appName
    , categories ? [ ]
    , desktopName
    , wmClass
    , comment ? null
    , icon ? null
    , faviconDomain ? baseDomainFor url
    , faviconHash ? null
    , faviconSize ? 192
    , profile
    , profileDirName ? appName
    , url
    , runtime ? { }
    , keywords ? [ ]
    , meta ? { }
    ,
    }:
    let
      policy = lib.recursiveUpdate policyBase (runtime.policyOverrides or { });
      policyFile = pkgs.writeText "${appName}-managed-policy.json" (builtins.toJSON policy);
      policyTree = pkgs.runCommand "${appName}-policy-tree" { } ''
        install -Dm444 ${policyFile} \
          "$out/share/chromium/policies/managed/${appName}.json"
      '';
      resolvedIcon =
        if icon != null then
          icon
        else if faviconHash != null then
          pkgs.fetchurl
            {
              name = "${appName}-favicon.png";
              url = "https://twenty-icons.com/${faviconDomain}/${toString faviconSize}";
              hash = faviconHash;
            }
        else
          throw "mkHeliumApp ${appName}: set icon or faviconHash";
      flags = lib.lists.unique (defaultFlags ++ (runtime.extraFlags or [ ]) ++ [ "--class=${wmClass}" ]);
      flagArgs = lib.concatMapStringsSep " " lib.escapeShellArg flags;
      launcher = pkgs.writeShellApplication {
        name = appName;
        runtimeInputs = [ pkgs.local.helium-browser ];
        text = ''
          export CHROME_POLICY_FILES_DIR=${policyTree}/share/chromium/policies

          exec helium-browser \
            --app=${lib.escapeShellArg url} \
            --user-data-dir="''${XDG_CONFIG_HOME:-$HOME/.config}/helium-browser/${profileDirName}" \
            --profile-directory=${lib.escapeShellArg profile} \
            ${flagArgs} \
            "$@"
        '';
      };
      desktopItem = pkgs.makeDesktopItem {
        name = appName;
        exec = "${appName} %U";
        inherit
          categories
          comment
          desktopName
          keywords
          ;
        icon = appName;
        terminal = false;
        startupNotify = true;
        startupWMClass = wmClass;
        extraConfig = {
          "X-GNOME-UsesNotifications" = "true";
          "X-KDE-StartupNotify" = "true";
        };
      };
      iconExtension = iconExtensionFor resolvedIcon;
      iconDirectory = iconDirectoryFor iconExtension;
      iconTheme = pkgs.runCommand "${appName}-icons" { } ''
        install -Dm444 ${resolvedIcon} \
          "$out/share/icons/hicolor/${iconDirectory}/apps/${appName}.${iconExtension}"
      '';
    in
    pkgs.symlinkJoin {
      name = appName;
      paths = [
        launcher
        desktopItem
        iconTheme
      ];

      passthru.heliumWebapp = {
        inherit policyFile flags;
      };

      meta = lib.recursiveUpdate
        {
          description = "${desktopName} web app launcher using Helium";
          homepage = url;
          license = pkgs.local.helium-browser.meta.license or lib.licenses.gpl3Plus;
          platforms = [ "x86_64-linux" ];
          mainProgram = appName;
          maintainers = [ ];
        }
        meta;
    };
}
