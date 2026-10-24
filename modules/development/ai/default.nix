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
                upstreamWrapper = ''
                  wrapProgram $out/bin/agent-browser \
                    --set AGENT_BROWSER_EXECUTABLE_PATH ${chromium}/bin/chromium
                '';
                browserPath = pkgs.lib.makeBinPath [
                  pkgs.local.lightpanda
                  chromium
                ];
              in
              assert pkgs.lib.assertMsg
                (pkgs.lib.hasInfix (builtins.unsafeDiscardStringContext upstreamWrapper) previous.postInstall)
                "Review the agent-browser wrapper: upstream postInstall changed";
              {
                # Avoid the generic executable path: agent-browser applies it to every engine.
                postInstall = pkgs.lib.replaceStrings
                  [ upstreamWrapper ]
                  [
                    ''
                      wrapProgram $out/bin/agent-browser --set AGENT_BROWSER_ENGINE lightpanda --prefix PATH : ${browserPath}
                    ''
                  ]
                  previous.postInstall;
              }
            )
        else
          llmAgents.agent-browser;
    in
    {
      environment.systemPackages = [
        llmAgents.codex
        llmAgents.claude-code
        llmAgents.openspec
        agentBrowser
        pkgs.local.caliper
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
