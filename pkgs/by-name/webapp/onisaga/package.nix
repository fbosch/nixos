{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "onisaga";
  categories = [
    "Graphics"
    "Viewer"
  ];
  desktopName = "OniSaga";
  wmClass = "OniSaga";
  comment = "Read manga online";
  icon = ./onisaga.png;
  profile = "OniSagaProfile";
  url = "https://onisaga.com/home";
  rememberLastPage = true;
  runtime.extraFlags = [
    "--hide-scrollbars"
  ];
  runtime.waylandAppId = "onisaga";
  keywords = [
    "manga"
    "manhwa"
    "manhua"
    "webapp"
    "helium"
  ];
}
