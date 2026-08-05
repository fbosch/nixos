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

      system.activationScripts.postActivation.text = lib.mkAfter ''
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx analyticsAllowed -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx afterScreenshotActions -array 0 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx afterVideoActions -array 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx annotateLastHighlightShape -int 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx annotateLastPixelateStyle -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx annotateLastTextSize -int 30
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx annotateShowMoreGradients -int 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx annotateTextStyle -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx captureWithoutDesktopIcons -int 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx deletePopupAfterDragging -int 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx popupAskForDestinationWhenSaving -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx popupSize -int 2
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx snapInAnnotateCrop -int 1
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx SUAutomaticallyUpdate -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx SUEnableAutomaticChecks -int 0
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx transparentWindowBackground -int 0

        # CleanShot stores keyboard shortcuts as plist data containing JSON.
        # These mirror the Hyprland capture bindings where macOS can express them.
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeArea -data 7b22636172626f6e4b6579223a382c22636172626f6e4d6f64696669657273223a343630387d
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeFullscreen -data 7b22636172626f6e4b6579223a3130352c22636172626f6e4d6f64696669657273223a307d
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeOCR -data 7b22636172626f6e4b6579223a33312c22636172626f6e4d6f64696669657273223a343630387d
        sudo -u ${username} killall cfprefsd 2>/dev/null || true
      '';
    };
}
