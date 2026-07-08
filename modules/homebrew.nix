{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.darwin.homebrew =
    { config, ... }:
    let
      hosts = flakeConfig.flake.meta.hosts or [ ];
      currentHost = lib.findFirst (host: host.name == config.networking.hostName) null hosts;
      isCorporateHost = currentHost != null && (currentHost.corporate or false);
    in
    {
      homebrew = {
        enable = true;
        onActivation = lib.mkMerge [
          {
            autoUpdate = false;
            upgrade = false;
          }
          (lib.mkIf (!isCorporateHost) {
            cleanup = "zap";
            extraFlags = [ "--force-cleanup" ];
          })
        ];

        taps = [
          "steipete/tap"
        ];

        extraConfig = ''
          tap "FelixKratz/formulae", "https://github.com/FelixKratz/homebrew-formulae", trusted: true
          brew "FelixKratz/formulae/borders", trusted: true

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
          "hazeover"
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
