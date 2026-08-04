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

  originFor =
    url:
    let
      match = builtins.match "^([a-zA-Z][a-zA-Z0-9+.-]*://[^/:?#]+).*" url;
    in
    if match == null then
      throw "mkHeliumApp: cannot infer origin from URL ${url}"
    else
      builtins.head match;

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
    , rememberLastPage ? false
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
      origin = originFor url;
      profilePath = "\${XDG_CONFIG_HOME:-$HOME/.config}/helium-browser/${profileDirName}";
      historyPath = "${profilePath}/${profile}/History";
      lastPageQuery = lib.escapeShellArg "SELECT url FROM urls WHERE url LIKE '${origin}/%' ORDER BY last_visit_time DESC LIMIT 1;";
      enableWidevine = runtime.enableWidevine or false;
      waylandAppId = runtime.waylandAppId or null;
      needsProcessExit = rememberLastPage || waylandAppId != null;
      browserCommand =
        if waylandAppId == null then "helium-browser" else "/run/current-system/sw/bin/helium-browser";
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
      unpackedExtensions = runtime.unpackedExtensions or [ ];
      extensionFlags = lib.optionals (unpackedExtensions != [ ]) [
        "--disable-features=ExtensionDisableUnsupportedDeveloper"
        "--load-extension=${lib.concatStringsSep "," (map toString unpackedExtensions)}"
      ];
      flags = lib.lists.unique (
        lib.optional (unpackedExtensions == [ ]) "--disable-extensions"
        ++ defaultFlags
        ++ extensionFlags
        ++ (runtime.extraFlags or [ ])
        ++ [ "--class=${wmClass}" ]
      );
      flagArgs = lib.concatMapStringsSep " " lib.escapeShellArg flags;
      launcher = pkgs.writeShellApplication {
        name = appName;
        runtimeInputs = [
          pkgs.local.helium-browser
        ]
        ++ lib.optionals enableWidevine [
          pkgs.google-chrome
          pkgs.local.helium-browser.passthru.widevineSetup
        ]
        ++ lib.optional rememberLastPage pkgs.sqlite
        ++ lib.optional (waylandAppId != null) pkgs.local.filterway;
        text = ''
          export CHROME_POLICY_FILES_DIR=${policyTree}/share/chromium/policies

          ${lib.optionalString enableWidevine ''
            helium-widevine-setup --user-data-dir="${profilePath}"
          ''}

          ${
            if needsProcessExit then
              ''
                launch_url=${lib.escapeShellArg url}
                ${lib.optionalString rememberLastPage ''
                  state_file="${profilePath}/last-url"

                  if [ -r "$state_file" ]; then
                    last_url="$(< "$state_file")"
                    case "$last_url" in
                      ${origin}|${origin}/*) launch_url="$last_url" ;;
                    esac
                  fi

                  if [ "$launch_url" = ${lib.escapeShellArg url} ] && [ -r "${historyPath}" ]; then
                    last_url="$(sqlite3 "${historyPath}" ${lastPageQuery} || true)"
                    case "$last_url" in
                      ${origin}|${origin}/*) launch_url="$last_url" ;;
                    esac
                  fi
                ''}

                ${lib.optionalString (waylandAppId != null) ''
                  : "''${XDG_RUNTIME_DIR:?${appName} requires XDG_RUNTIME_DIR}"
                  : "''${WAYLAND_DISPLAY:?${appName} requires native Wayland}"

                  upstream="$WAYLAND_DISPLAY"
                  case "$upstream" in
                    /*) ;;
                    *) upstream="$XDG_RUNTIME_DIR/$upstream" ;;
                  esac

                  downstream="wayland-${appName}-$$"
                  filterway --upstream "$upstream" --downstream "$XDG_RUNTIME_DIR/$downstream" --app-id ${lib.escapeShellArg waylandAppId} &
                  filterway_pid=$!

                  for _ in {1..50}; do
                    [ -S "$XDG_RUNTIME_DIR/$downstream" ] && break
                    if ! kill -0 "$filterway_pid" 2>/dev/null; then
                      wait "$filterway_pid" 2>/dev/null || true
                      exit 1
                    fi
                    sleep 0.1
                  done

                  if [ ! -S "$XDG_RUNTIME_DIR/$downstream" ]; then
                    kill "$filterway_pid" 2>/dev/null || true
                    wait "$filterway_pid" 2>/dev/null || true
                    exit 1
                  fi
                ''}

                app_status=0
                ${lib.optionalString (waylandAppId != null) "WAYLAND_DISPLAY=\"$downstream\" "}${browserCommand} \
                  --app="$launch_url" \
                  --user-data-dir="${profilePath}" \
                  --profile-directory=${lib.escapeShellArg profile} \
                  ${flagArgs} \
                  "$@" || app_status=$?

                ${lib.optionalString rememberLastPage ''
                  if [ -r "${historyPath}" ]; then
                    last_url="$(sqlite3 "${historyPath}" ${lastPageQuery} || true)"
                    case "$last_url" in
                      ${origin}|${origin}/*) printf '%s\n' "$last_url" > "$state_file" ;;
                    esac
                  fi
                ''}

                ${lib.optionalString (waylandAppId != null) ''
                  kill "$filterway_pid" 2>/dev/null || true
                  wait "$filterway_pid" 2>/dev/null || true
                ''}

                exit "$app_status"
              ''
            else
              ''
                exec helium-browser \
                  --app=${lib.escapeShellArg url} \
                  --user-data-dir="${profilePath}" \
                  --profile-directory=${lib.escapeShellArg profile} \
                  ${flagArgs} \
                  "$@"
              ''
          }
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
        icon = "${iconTheme}/share/icons/hicolor/${iconDirectory}/apps/${appName}.${iconExtension}";
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
      iconTheme =
        pkgs.runCommand "${appName}-icons"
          (lib.optionalAttrs (iconExtension == "png") {
            nativeBuildInputs = [ pkgs.imagemagick ];
          })
          (
            if iconExtension == "png" then
              ''
                install -d "$out/share/icons/hicolor/${iconDirectory}/apps"
                magick ${resolvedIcon} -resize 512x512 -background none -gravity center -extent 512x512 \
                  "$out/share/icons/hicolor/${iconDirectory}/apps/${appName}.${iconExtension}"
              ''
            else
              ''
                install -Dm444 ${resolvedIcon} \
                  "$out/share/icons/hicolor/${iconDirectory}/apps/${appName}.${iconExtension}"
              ''
          );
    in
    pkgs.symlinkJoin {
      name = appName;
      paths = [
        launcher
        desktopItem
        iconTheme
      ];

      passthru.heliumWebapp = {
        inherit
          flags
          policyFile
          unpackedExtensions
          waylandAppId
          enableWidevine
          ;
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
