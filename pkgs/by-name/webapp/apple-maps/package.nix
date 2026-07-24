{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "apple-maps";
  categories = [
    "Geography"
    "Network"
  ];
  desktopName = "Apple Maps";
  wmClass = "Apple Maps";
  comment = "Apple Maps web app";
  icon = pkgs.fetchurl {
    url = "https://commons.wikimedia.org/wiki/Special:Redirect/file/Apple_Maps_iOS_26_icon.png";
    hash = "sha256-jM0To/VE50ODKaZuEM39WNLuwuo47MOqQaknmWt8+jU=";
  };
  profile = "AppleMapsProfile";
  url = "https://maps.apple.com/";
  runtime.policyOverrides.DefaultGeolocationSetting = 1;
}
