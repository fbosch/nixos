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
  };
}
