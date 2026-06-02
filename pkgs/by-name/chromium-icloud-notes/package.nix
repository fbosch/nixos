{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-icloud-notes";
  categories = [
    "Office"
    "Utility"
  ];
  class = "iCloud Notes";
  desktopName = "iCloud Notes";
  comment = "Apple iCloud Notes web app";
  icon = ./icloud-notes.svg;
  profile = "ICloudNotesProfile";
  url = "https://www.icloud.com/notes";
  runtime = {
    extraFlags = [
      "--hide-scrollbars"
      "--site-per-process"
      "--isolate-origins=https://www.icloud.com"
    ];
  };
}
