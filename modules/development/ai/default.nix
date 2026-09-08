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
      agentBrowser =
        if pkgs.stdenv.hostPlatform.isLinux then
          pkgs.writeShellApplication
            {
              name = "agent-browser";
              # Upstream's Linux wrapper forces Chromium through the environment.
              # CLI flags override it; keep user arguments last for explicit overrides.
              text = ''
                exec ${pkgs.lib.getExe llmAgents.agent-browser} \
                  --engine lightpanda \
                  --executable-path ${pkgs.lib.getExe pkgs.local.lightpanda} \
                  "$@"
              '';
            }
        else
          llmAgents.agent-browser;
    in
    {
      environment.systemPackages =
        [
          llmAgents.codex
          llmAgents.openspec
          agentBrowser
        ]
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
