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

        taps = [
          "steipete/tap"
        ];

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
          "obsidian"
          "podman-desktop"
          "codexbar"
        ];

        brews = [ ];
      };
    };
}
