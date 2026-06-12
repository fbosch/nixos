{ config, ... }:
{
  flake.modules.darwin."hosts/rvn-mac-corp/cleanshot" =
    { lib, ... }:
    let
      username = config.flake.meta.user.username;
    in
    {
      system.activationScripts.postActivation.text = lib.mkAfter ''
        # CleanShot stores keyboard shortcuts as plist data containing JSON.
        # These mirror the Hyprland capture bindings where macOS can express them.
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeArea -data 7b22636172626f6e4b6579223a382c22636172626f6e4d6f64696669657273223a343630387d
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeFullscreen -data 7b22636172626f6e4b6579223a3130352c22636172626f6e4d6f64696669657273223a307d
        sudo -u ${username} defaults write pl.maketheweb.cleanshotx LAVAtakeOCR -data 7b22636172626f6e4b6579223a33312c22636172626f6e4d6f64696669657273223a343630387d
        sudo -u ${username} killall cfprefsd 2>/dev/null || true
      '';
    };
}
