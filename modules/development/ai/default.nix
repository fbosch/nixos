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
      pi = llmAgents.pi.overrideAttrs (
        previous:
        assert pkgs.lib.assertMsg (
          previous.version == "0.85.0"
        ) "Review pi-openai-capabilities.patch before upgrading Pi from 0.85.0";
        {
          patches = (previous.patches or [ ]) ++ [ ./pi-selector-overlays.patch ];
          # These dependency files exist only after configure, before Bun compiles Pi.
          postConfigure = (previous.postConfigure or "") + ''
            # WezTerm fullscreen image fix; remove after upstream #8306 is fixed.
            patch -d node_modules/@earendil-works/pi-tui -p1 \
              < ${./pi-fullscreen-images.patch}
            patch --batch --fuzz=0 -p1 < ${./pi-openai-capabilities.patch}
            PI_NATIVE_TEST_ROOT="$PWD" bun test ${./tests}
          '';
        }
      );
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
  homeManagerPi =
    { lib, pkgs, ... }:
    {
      home.activation.securePiAgentDirectory =
        lib.hm.dag.entryBetween [ "dotfiles" ] [ "writeBoundary" "linkGeneration" ]
          ''
            set -euo pipefail

            $DRY_RUN_CMD ${pkgs.coreutils}/bin/install -d -m 0700 "$HOME/.pi/agent"
          '';
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

      homeManager.development = homeManagerPi;

    };
  };

  perSystem =
    { lib, pkgs, ... }:
    let
      piHomeConfig =
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            homeManagerPi
            {
              home = {
                username = "tester";
                homeDirectory = "/home/tester";
                stateVersion = "25.05";
              };
            }
          ];
        }).config;
      securePiAgentDirectory = piHomeConfig.home.activation.securePiAgentDirectory;
    in
    {
      nix-unit.tests.piActivation = {
        testSecuresPiAgentDirectory = {
          expr = lib.hasInfix ''/bin/install -d -m 0700 "$HOME/.pi/agent"'' securePiAgentDirectory.data;
          expected = true;
        };
        testRunsBeforeDotfiles = {
          expr = securePiAgentDirectory.before;
          expected = [ "dotfiles" ];
        };
        testRunsAfterHomeManagerWrites = {
          expr = securePiAgentDirectory.after;
          expected = [
            "writeBoundary"
            "linkGeneration"
          ];
        };
      };
    };
}
