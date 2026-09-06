{ inputs, ... }:
let
  systemPackages =
    { pkgs, ... }:
    let
      llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      pi = llmAgents.pi.overrideAttrs (
        previous:
          assert pkgs.lib.assertMsg
            (
              previous.version == "0.85.1"
            ) "Review Pi patches before upgrading Pi from 0.85.1";
          {
            patches = (previous.patches or [ ]) ++ [ ./pi-selector-overlays.patch ];
            # These dependency files exist only after configure, before Bun compiles Pi.
            postConfigure = (previous.postConfigure or "") + ''
              # WezTerm fullscreen image fix; remove after upstream #8306 is fixed.
              patch -d node_modules/@earendil-works/pi-tui -p1 \
                < ${./pi-fullscreen-images.patch}
              patch --batch --fuzz=0 -p1 < ${./pi-openai-capabilities.patch}
              patch --batch --fuzz=0 -p1 < ${./pi-auth-profiles-startup.patch}
              patch --batch --fuzz=0 -p1 < ${./pi-code-mode.patch}
            '';
          }
      );
    in
    {
      environment.systemPackages = [ pi ];
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
  flake.modules = {
    nixos.development.imports = [ systemPackages ];
    darwin.development.imports = [ systemPackages ];
    homeManager.development = homeManagerPi;
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
