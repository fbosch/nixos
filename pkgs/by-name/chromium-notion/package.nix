{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-notion";
  categories = [ "Office" "Utility" ];
  class = "Notion";
  desktopName = "Notion";
  comment = "All-in-one workspace for notes and collaboration";
  icon = ./notion-logo.png;
  profile = "NotionProfile";
  url = "https://www.notion.so";
  hardening = {
    extraFlags = [ "--hide-scrollbars" ];
  };
}
