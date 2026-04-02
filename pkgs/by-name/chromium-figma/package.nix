{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-figma";
  categories = [
    "Graphics"
    "Office"
  ];
  class = "Figma";
  desktopName = "Figma";
  comment = "Collaborative interface design and prototyping";
  icon = ./figma-logo.svg;
  profile = "FigmaProfile";
  url = "https://www.figma.com";
  runtime = {
    extraFlags = [ "--hide-scrollbars" ];
    policyOverrides = {
      # Figma opens external links and authentication windows.
      DefaultPopupsSetting = 1;
    };
  };
}
