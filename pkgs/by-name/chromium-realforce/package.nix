{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-realforce";
  categories = [ "Utility" "Network" ];
  class = "Realforce";
  desktopName = "Realforce Connect";
  comment = "Realforce keyboard configuration and firmware update tool";
  icon = ./realforce-connect.png;
  profile = "RealforceConnectProfile";
  url = "https://realforce-connect.online";
  hardening = {
    extraFlags = [
      "--hide-scrollbars"
      "--user-agent=\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\""
    ];
    policyOverrides = {
      # Allow WebHID access for keyboard configuration
      DefaultWebHidGuardSetting = 1; # 1 = Allow sites to ask for HID device access
      # Allow the Realforce Connect website to access HID devices
      WebHidAllowDevicesForUrls = [
        {
          devices = [
            { vendor_id = 2131; product_id = 791; } # Topre REALFORCE X1U (0x0853:0x0317)
          ];
          urls = [ "https://realforce-connect.online" ];
        }
      ];
    };
  };
}
