{ inputs, ... }:
let
  numtideCache = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
  systemPackages =
    { hostMeta, pkgs, ... }:
    let
      llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      pi = llmAgents.pi.overrideAttrs (previous: {
        patches = (previous.patches or [ ]) ++ [ ./pi-selector-overlays.patch ];
      });
    in
    {
      environment.systemPackages =
        (with llmAgents; [
          codex
          openspec
          agent-browser
        ])
        ++ [ pi ]
        ++ pkgs.lib.optionals (!(hostMeta.corporate or false)) [ llmAgents.opencode ]
        ++ [
          pkgs.tesseract
          inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];
    };
in
{
  flake = {
    modules = {
      nixos.development = {
        imports = [ systemPackages ];
        nix.settings = numtideCache;
      };

      darwin.development =
        { hostMeta, ... }:
        let
          isDeterminate = (hostMeta.nixDistribution or null) == "determinate";
        in
        {
          imports = [ systemPackages ];
        }
        // (
          if isDeterminate then
            {
              determinateNix.customSettings = numtideCache;
            }
          else
            {
              nix.settings = numtideCache;
            }
        );

    };
  };
}
