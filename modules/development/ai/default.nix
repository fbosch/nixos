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
          llmAgents.agent-browser.overrideAttrs
            (
              previous:
              let
                chromium = builtins.head previous.buildInputs;
                browserPath = pkgs.lib.makeBinPath [
                  pkgs.local.lightpanda
                  chromium
                ];
              in
              assert pkgs.lib.assertMsg
                (
                  previous.version == "0.37.1"
                ) "Review the agent-browser wrapper before upgrading from 0.37.1";
              {
                # Avoid the generic executable path: agent-browser applies it to every engine.
                postInstall = ''
                  mkdir -p $out/share/agent-browser
                  cp -r ../skills ../skill-data $out/share/agent-browser/
                  wrapProgram $out/bin/agent-browser \
                    --set AGENT_BROWSER_ENGINE lightpanda \
                    --prefix PATH : ${browserPath}
                '';
              }
            )
        else
          llmAgents.agent-browser;
    in
    {
      environment.systemPackages = [
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
