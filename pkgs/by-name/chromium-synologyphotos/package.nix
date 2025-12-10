{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-synologyphotos";
  categories = [ "Graphics" "Photography" "Network" ];
  class = "chromium-synologyphotos";
  desktopName = "Synology Photos";
  comment = "Personal photo management and backup";
  icon = ./synology-photos.png;
  profile = "SynologyPhotosProfile";
  url = "https://photos.corvus-corax.synology.me";
  hardening = {
    extraFlags = [ "--hide-scrollbars" ];
  };
}
