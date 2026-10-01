{ inputs, ... }:
let
  systemPackages =
    { pkgs, ... }:
    let
      llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      piCompile = "bun build --compile ./dist/bun/cli.js ./src/utils/image-resize-worker.ts";
      pi = llmAgents.pi.overrideAttrs (
        previous:
        assert pkgs.lib.assertMsg (previous.version == "0.99.1")
          "Review the Pi auth-startup and selector patches, codemode worker packaging, and pi-server workaround before upgrading from 0.99.1";
        assert pkgs.lib.assertMsg (pkgs.lib.hasInfix piCompile previous.preInstall)
          "Review Pi codemode worker packaging: upstream's compile command changed";
        {
          patches = (previous.patches or [ ]) ++ [
            ./pi-selector-overlays.patch
            ./pi-auth-startup.patch
          ];
          # The npm tarball has only dist/; preserve upstream's embedded src/ worker path.
          preInstall = ''
            mkdir -p src/extensions/codemode
            echo 'import "../../../dist/extensions/codemode/worker.js";' > src/extensions/codemode/worker.ts
          ''
          +
            pkgs.lib.replaceStrings [ piCompile ] [ "${piCompile} ./src/extensions/codemode/worker.ts" ]
              previous.preInstall;
          postInstallCheck = (previous.postInstallCheck or "") + ''
            PI_TEST_BINARY="$out/bin/pi" node --test ${./__tests__/codemode-worker.test.mjs}
          '';
          postConfigure = (previous.postConfigure or "") + ''
            # llm-agents injects pi-server even though upstream already declares it.
            awk '/"@earendil-works\/pi-server"/ { if (seen++) next } { print }' package.json > package.json.tmp
            mv package.json.tmp package.json
            PI_OFFLINE=1 PI_TEST_PACKAGE="$PWD" node --test ${./__tests__/auth-startup.test.mjs}
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
