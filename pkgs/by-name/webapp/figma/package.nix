{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "figma";
  categories = [
    "Graphics"
    "Office"
  ];
  desktopName = "Figma";
  wmClass = "Figma";
  comment = "Collaborative interface design and prototyping";
  icon = ./figma-logo.png;
  faviconHash = "sha256-6jbscXE6xD7cbGr7THJ0dCSy35Iaw2uhfXwVf4rLvI8=";
  profile = "FigmaProfile";
  url = "https://www.figma.com";
  runtime = {
    extraFlags = [ "--hide-scrollbars" ];
    policyOverrides = {
      DefaultPopupsSetting = 1;
    };
  };
}
