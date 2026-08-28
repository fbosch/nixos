{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "8bitdo-firmware-updater";
  categories = [
    "Settings"
    "HardwareSettings"
    "Game"
  ];
  desktopName = "8BitDo Firmware Updater";
  wmClass = "8BitDo Firmware Updater";
  comment = "Update firmware on 8BitDo controllers and receivers";
  icon = ./icon.png;
  profile = "EightBitDoFirmwareUpdaterProfile";
  url = "https://web.8bitdo.com/browser-support";
  runtime = {
    allowHostDevices = true;
    policyOverrides.WebHidAskForUrls = [ "https://web.8bitdo.com" ];
  };
  keywords = [
    "8bitdo"
    "controller"
    "gamepad"
    "firmware"
    "webhid"
  ];
}
