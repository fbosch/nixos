{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "synologyphotos";
  categories = [
    "Graphics"
    "Photography"
    "Network"
  ];
  desktopName = "Synology Photos";
  wmClass = "Synology Photos";
  comment = "Personal photo management and backup";
  icon = ./synology-photos.png;
  profile = "SynologyPhotosProfile";
  url = "https://photos.corvus-corax.synology.me";
  runtime.extraFlags = [ "--hide-scrollbars" ];
}
