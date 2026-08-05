{ inputs, ... }:
let
  numtideCache = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
in
{
  flake = {
    modules = {
      nixos.development = {
        nix.settings = numtideCache;
      };

      darwin.development =
        { hostMeta, ... }:
        let
          isDeterminate = (hostMeta.nixDistribution or null) == "determinate";
        in
        if isDeterminate then
          {
            determinateNix.customSettings = numtideCache;
          }
        else
          {
            nix.settings = numtideCache;
          };

      homeManager.development =
        { hostMeta, pkgs, ... }:
        let
          inherit (pkgs) lib;

          llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
          llmAgentPackages = with llmAgents;
            [
              codex
              openspec
              agent-browser
            ]
            ++ lib.optionals (!(hostMeta.corporate or false)) [ opencode ];

        in
        {
          config = {
            home.packages = lib.flatten [
              llmAgentPackages
              (with pkgs; [
                tesseract
                inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default
              ])
            ];
          };
        };
    };
  };
}
