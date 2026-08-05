{ config, ... }:
let
  personalUsername = config.flake.meta.user.username;
in
{
  flake.modules.darwin.cleanshot =
    { lib, hostMeta, ... }:
    let
      username = if hostMeta.corporate or false then hostMeta.primaryUser else personalUsername;
    in
    {
      homebrew.casks = [ "cleanshot" ];

      system.defaults.CustomUserPreferences."pl.maketheweb.cleanshotx" = {
        analyticsAllowed = 0;
        afterScreenshotActions = [ 0 1 ];
        afterVideoActions = [ 0 ];
        annotateLastHighlightShape = 1;
        annotateLastPixelateStyle = 0;
        annotateLastTextSize = 30;
        annotateShowMoreGradients = 1;
        annotateTextStyle = 0;
        captureWithoutDesktopIcons = 1;
        deletePopupAfterDragging = 1;
        popupAskForDestinationWhenSaving = 0;
        popupSize = 2;
        snapInAnnotateCrop = 1;
        SUAutomaticallyUpdate = 0;
        SUEnableAutomaticChecks = 0;
        transparentWindowBackground = 0;
      };

      system.activationScripts.postActivation.text = lib.mkAfter ''
        cleanshot_shortcut() {
          sudo -u ${lib.escapeShellArg username} defaults write pl.maketheweb.cleanshotx "$1" -data "$2"
        }

        # CleanShot stores keyboard shortcuts as plist data containing JSON.
        # These mirror the Hyprland capture bindings where macOS can express them.
        cleanshot_shortcut LAVAtakeArea 7b22636172626f6e4b6579223a382c22636172626f6e4d6f64696669657273223a343630387d
        cleanshot_shortcut LAVAtakeFullscreen 7b22636172626f6e4b6579223a3130352c22636172626f6e4d6f64696669657273223a307d
        cleanshot_shortcut LAVAtakeOCR 7b22636172626f6e4b6579223a33312c22636172626f6e4d6f64696669657273223a343630387d
        sudo -u ${lib.escapeShellArg username} killall cfprefsd 2>/dev/null || true
      '';
    };
}
