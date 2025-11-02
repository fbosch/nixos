{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-protoncalendar";
  categories = [ "Network" "Office" "Calendar" ];
  class = "chromium-protoncalendar";
  desktopName = "Proton Calendar";
  comment = "Secure encrypted calendar";
  icon = ./proton-calendar.svg;
  profile = "ProtonCalendarProfile";
  url = "https://calendar.proton.me";
  hardening = {
    extraFlags = [ "--hide-scrollbars" ];
  };
}
