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
        onActivation = {
          autoUpdate = false;
          upgrade = false;
        }
        // lib.optionalAttrs (!isCorporateHost) {
          cleanup = "zap";
          extraFlags = [ "--force-cleanup" ];
        };

        taps = [
          "FelixKratz/formulae"
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
          "borders"
          "mas"
          "mole"
          "rtk"
        ];
      };
    };
}
