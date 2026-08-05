{ lib, ... }:
{
  flake.modules.darwin.homebrew =
    { hostMeta, ... }:
    let
      isCorporateHost = hostMeta.corporate or false;
    in
    {
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = false;
          cleanup = "zap";
          extraFlags = [ "--force-cleanup" ];
          upgrade = false;
        };

        taps = [
          "steipete/tap"
        ];

        extraConfig = ''
          tap "FelixKratz/formulae", "https://github.com/FelixKratz/homebrew-formulae", trusted: true
          brew "FelixKratz/formulae/borders", trusted: true

          tap "lightpanda-io/browser", trusted: true
          brew "lightpanda-io/browser/lightpanda", trusted: true
        '';

        casks =
          [
            "numi"
            "floorp"
            "firefox"
            "arc"
            "zen"
          ]
          ++ lib.optionals (!isCorporateHost) [
            "helium-browser"
            "tailscale"
          ]
          ++ [
            "hazeover"
            "alt-tab"
            "replacicon"
            "cursor"
            "figma"
            "cleanshot"
            "obsidian"
            "linear"
            "bentobox"
            "bitwarden"
            "font-sf-pro"
            "vicinae"
          ];

        brews = [
          "biome"
          "mas"
          "mole"
          "rtk"
          "worktrunk"
        ];
      };
    };
}
