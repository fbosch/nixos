{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "icloud-notes";
  categories = [
    "Office"
    "Utility"
  ];
  desktopName = "iCloud Notes";
  wmClass = "iCloud Notes";
  comment = "Apple iCloud Notes web app";
  icon = ./icloud-notes.svg;
  faviconHash = "sha256-fU/iWGqRnbid1AvGaaSv2lRZCIOHLjlBu/7vyj0iuLs=";
  profile = "ICloudNotesProfile";
  url = "https://www.icloud.com/notes";
  runtime.extraFlags = [
    "--hide-scrollbars"
    "--site-per-process"
    "--isolate-origins=https://www.icloud.com"
  ];
}
