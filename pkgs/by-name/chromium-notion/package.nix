{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-notion";
  categories = [ "Office" "Utility" ];
  class = "chromium-notion";
  desktopName = "Notion";
  comment = "All-in-one workspace for notes and collaboration";
  icon = ./Notion-logo.svg;
  profile = "NotionProfile";
  url = "https://www.notion.so";
}
