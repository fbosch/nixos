{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-protoncalendar";
  categories = [ "Network" "Office" "Calendar" ];
  class = "chrome-calendar.proton.me_-CalendarProfile";
  desktopName = "Proton Calendar";
  icon = ./proton-calendar.svg;
  profile = "ProtonCalendarProfile";
  url = "https://calendar.proton.me";
}
