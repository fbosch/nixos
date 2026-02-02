{
  flake.modules.darwin.homebrew =
    _:
    {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap";
          upgrade = true;
        };

        casks = [
          "raycast"
          "numi"
          "font-noto-sans-runic"
          "floorp"
          "firefox"
          "arc"
          "zen"
          "helium-browser"
          "alt-tab"
          "replacicon"
          "cursor"
          "figma"
          "cleanshot"
          "steipete/tap/codexbar"
          "obsidian"
        ];

        brews = [ ];
      };
    };
}
