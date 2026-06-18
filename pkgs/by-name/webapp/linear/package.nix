{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "linear";
  categories = [
    "Office"
    "ProjectManagement"
  ];
  desktopName = "Linear";
  wmClass = "Linear";
  comment = "Issue tracking and project management";
  icon = ./linear-logo.png;
  faviconHash = "sha256-yEDF/eS1He8uaDlbvrtqofMR1pQix6jB5kQepBAoSEY=";
  profile = "LinearProfile";
  url = "https://linear.app";
  runtime.extraFlags = [ "--hide-scrollbars" ];
}
