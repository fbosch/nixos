{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "notion";
  categories = [
    "Office"
    "Utility"
  ];
  desktopName = "Notion";
  wmClass = "Notion";
  comment = "All-in-one workspace for notes and collaboration";
  icon = ./notion-logo.png;
  faviconHash = "sha256-L2vKO9FuR1fUHmaPjFmFbmXFJnXu4Pe5NvjlImoe9Ns=";
  profile = "NotionProfile";
  url = "https://www.notion.so";
  runtime.extraFlags = [ "--hide-scrollbars" ];
}
