{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-linear";
  categories = [
    "Office"
    "ProjectManagement"
  ];
  class = "Linear";
  desktopName = "Linear";
  comment = "Issue tracking and project management";
  icon = ./linear-logo.svg;
  profile = "LinearProfile";
  url = "https://linear.app";
  hardening = {
    extraFlags = [ "--hide-scrollbars" ];
  };
}
