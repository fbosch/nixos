{ inputs, ... }:
let
  systemPackages =
    { pkgs, ... }:
    let
      llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      pi = llmAgents.pi.overrideAttrs (
        previous:
          assert pkgs.lib.assertMsg (previous.version == "1.0.4")
            "Review the Pi auth-startup, selector, discovery, and MCP-background patches, codemode worker packaging, and pi-server workaround before upgrading from 1.0.4";
          assert pkgs.lib.assertMsg
            (
              pkgs.lib.hasInfix "./src/extensions/codemode/worker.ts" (previous.preInstall or "")
            ) "Review Pi codemode worker packaging: upstream's worker entry changed";
          assert pkgs.lib.assertMsg
            (
              pkgs.lib.hasInfix "--compile-autoload-package-json" (previous.preInstall or "")
            ) "Review Pi binary package.json autoloading: upstream's compile flags changed";
          {
            patches = (previous.patches or [ ]) ++ [
              ./pi-selector-overlays.patch
              ./pi-auth-startup.patch
              ./pi-tool-search-ranking.patch
              ./pi-mcp-background.patch
            ];
            postInstallCheck = (previous.postInstallCheck or "") + ''
              PI_TEST_BINARY="$out/bin/pi" node --test ${./__tests__/codemode-worker.test.mjs} ${./__tests__/tool-search-ranking.test.mjs}
            '';
            postConfigure = (previous.postConfigure or "") + ''
              # The Pi package source contains duplicate pi-server declarations.
              awk '/"@earendil-works\/pi-server"/ { if (seen++) next } { print }' package.json > package.json.tmp
              mv package.json.tmp package.json
              test "$(grep -Fc '"@earendil-works/pi-server"' package.json)" -eq 1
              PI_OFFLINE=1 PI_TEST_PACKAGE="$PWD" node --test ${./__tests__/auth-startup.test.mjs} ${./__tests__/mcp-background.test.mjs}
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
