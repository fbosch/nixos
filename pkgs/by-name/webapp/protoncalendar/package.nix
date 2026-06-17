{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "protoncalendar";
  categories = [
    "Network"
    "Office"
    "Calendar"
  ];
  desktopName = "Proton Calendar";
  wmClass = "Proton Calendar";
  comment = "Secure encrypted calendar";
  faviconHash = "sha256-IkLdXUeULtu3J8R9yQS8hbj4ZofhvG2uLW1/oDJSw5U=";
  profile = "ProtonCalendarProfile";
  url = "https://calendar.proton.me";
  runtime.extraFlags = [
    "--hide-scrollbars"
    "--site-per-process"
    "--isolate-origins=https://calendar.proton.me"
  ];
}
