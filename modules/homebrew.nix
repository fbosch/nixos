{
  flake.modules.darwin.homebrew =
    _:
    {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap";
          extraFlags = [ "--force-cleanup" ];
          upgrade = true;
        };

        taps = [
          "steipete/tap"
        ];

        extraConfig = ''
          tap "lightpanda-io/browser", trusted: true
          brew "lightpanda-io/browser/lightpanda", trusted: true
        '';

        casks = [
          "raycast"
          "numi"
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
          "codexbar"
          "linear"
          "bentobox"
          "bitwarden"
        ];

        brews = [
          "mas"
          "mole"
          "rtk"
        ];
      };
    };
}
