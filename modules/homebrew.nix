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
          "numi"
          "font-noto-sans-runic"
          "floorp"
          "arc"
          "zen"
          "alt-tab"
          "replacicon"
          "cursor"
          "figma"
          "steipete/tap/codexbar"
        ];

        brews = [ ];
      };
    };
}
