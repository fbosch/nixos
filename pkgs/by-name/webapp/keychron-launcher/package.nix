{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "keychron-launcher";
  categories = [
    "Settings"
    "HardwareSettings"
  ];
  desktopName = "Keychron Launcher";
  wmClass = "Keychron Launcher";
  comment = "Configure Keychron keyboards and mice";
  icon = pkgs.fetchurl {
    url = "https://www.keychron.com/cdn/shop/files/Icon-QMK_Launcher.svg?v=7325956401058275962";
    hash = "sha256-XWNEh7dfsEwpVNBFkQbhqsYfhkk/8LlYlstEhKLahqQ=";
  };
  profile = "KeychronLauncherProfile";
  url = "https://launcher.keychron.com/";
  runtime = {
    allowHostDevices = true;
    policyOverrides = {
      WebHidAskForUrls = [ "https://launcher.keychron.com" ];
      WebUsbAskForUrls = [ "https://launcher.keychron.com" ];
      SerialAskForUrls = [ "https://launcher.keychron.com" ];
    };
  };
  keywords = [
    "keychron"
    "keyboard"
    "mouse"
    "firmware"
    "webhid"
    "webusb"
  ];
}
