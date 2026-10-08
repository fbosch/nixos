{ inputs, ... }:
let
  mkPi = pkgs:
    let
      llmAgents = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system};
      pi = llmAgents.pi.overrideAttrs (
        previous:
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
            prePatch = (previous.prePatch or "") + ''
              # Keep the overlays tied to their exact upstream source pre-images.
              if ! sha256sum --check --strict <<'PI_PATCH_HASHES'
              0ba5c847b4fd2fd838f71ea84885b9f3a4f15d9bf4b5493e2e88a41d1507e20b  dist/core/agent-session.js
              ab5dac8701f02587db54abc27d119ea44ebd3708f235d5daf8293abd7b2ea71e  dist/core/agent-session-services.d.ts
              20b7aa4b0657b53fb522ea051df26f72901802e03cc06c89e0a8926388bca601  dist/core/agent-session-services.js
              fe5661c6cd9a948293f0f1d1db5a052dcc60493f6b1f68349a7ab96987b10e40  dist/core/extensions/index.d.ts
              61fae1c4347b04a0a486589f96fba1ca9676a89ae0a02e639c677e1f1e061298  dist/core/extensions/types.d.ts
              8155c0b7d819d2248a1bbf0fa4b8e40d15552ff7fa6a772154cbbccb6ae59235  dist/core/sdk.js
              b254e36846b1dcc64ce1a8ba72e23fb410df4aa4408ba8c23e69e5b3f934e3cc  dist/index.d.ts
              866d65f2d42f74d2bb72ed4a755c8ace1b8a2c497a32cb57cc4db594a4fcb2bf  dist/main.js
              ee7e759f8b1e3946226a87f3af5e9af74a5a65106888037b890d4680faaea2d5  dist/extensions/mcp/index.js
              4c54fc05028d76456e7201a862d79972dd440b8e4b1e29710cb76fd1ee72a5db  dist/core/settings-manager.d.ts
              7ded026cd47cbc9890e9e4e7076d2ee3182bfd43a8d9e9a567913af92581ff26  dist/core/settings-manager.js
              33de81fab8fa601ebb343647b659e3231c9c6dc54b55700c943314f4ee0a1793  dist/modes/interactive/components/settings-selector.d.ts
              d216c41063495cbb0da084e73e6c312a6ac350750d246cc3fcabd630dad7d86f  dist/modes/interactive/components/settings-selector.js
              23897899f877c836f3c4df1101496479e7e25090adbba1b65065ec6a2aa3f912  dist/modes/interactive/components/tree-selector.d.ts
              b5c2dcd16f535d93cae3d34fa4042d78604450b81fd82eb07cd0c97bd982f762  dist/modes/interactive/components/tree-selector.js
              05a3b023bedba884aac5f07cd1be2afcb17a20c83aa71c742d1058237609c765  dist/modes/interactive/components/user-message-selector.d.ts
              563e7619c28a6ee3626ee319e32fa1ccea88910fc3b08126df8ee49664d19cd6  dist/modes/interactive/components/user-message-selector.js
              0d51ca1dc90b763eb42ef402257cbf070f512fea3f6494e42a3990797fe27871  dist/modes/interactive/interactive-mode.js
              40883e4a63d6aaeb58e659f1151d02c8c26982fc109658fa72fb35a94ea109d2  docs/settings.md
              503de1c907882c0ee032ad83a30966f3edc095acf611f569bea573aec9730381  dist/extensions/codemode/execute.js
              cb0a990e5b70063f8368bc110ad48a2d411301a69c90ef0be857cd4af0466fad  dist/extensions/tool-search/tool.d.ts
              452956aa3bf67e8cdba4cabdb17431e12c958156eb77dbb7cbe8158cfcfa18d8  dist/extensions/tool-search/tool.js
              5482298b995db935f7b96f5d6056fa1c36ac6fc80456be594ef65b83c62b0d30  dist/index.js
              PI_PATCH_HASHES
              then
                echo "Pi patch target content changed; review the overlays before updating their source hashes." >&2
                exit 1
              fi
              if [ -e dist/core/extensions/model-availability.js ]; then
                echo "Pi patch target already exists; review pi-auth-startup.patch before updating." >&2
                exit 1
              fi
            '';
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
    pi;
  mkLauncher = pkgs:
    let
      rawPi = mkPi pkgs;
      profile = pkgs.writeText "pi-nono-profile.json" (builtins.toJSON (builtins.fromJSON (builtins.readFile ../nono/scripts/profile.json)));
    in
    pkgs.runCommand "pi"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "pi";
      }
      ''
        mkdir -p "$out/bin"
        mkdir -p "$out/share/pi"
        touch "$out/share/pi/nono-wrapper"
        # A binary entry avoids sourcing BASH_ENV before nono applies confinement.
        makeBinaryWrapper ${pkgs.nodejs}/bin/node "$out/bin/pi" \
          --unset NODE_OPTIONS --unset NODE_PATH \
          --add-flags "${../nono/scripts/launcher.mjs} ${pkgs.nono}/bin/nono ${rawPi}/bin/pi ${profile}"
        PI_TEST_BINARY="$out/bin/pi" ${pkgs.nodejs}/bin/node --test ${../nono}/__tests__/launcher.test.mjs
      '';
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = [ (mkLauncher pkgs) ];
  };
  homeManagerPi =
    { lib, pkgs, ... }:
    {
      home.activation.securePiAgentDirectory =
        lib.hm.dag.entryBetween [ "dotfiles" ] [ "writeBoundary" "linkGeneration" ]
          ''
            set -euo pipefail

            for ancestor in "$HOME" "$HOME/.pi" "$HOME/.pi/agent" "$HOME/.pi/agent/bin"; do
              if [ -L "$ancestor" ]; then
                echo "Refusing symlinked Pi activation ancestor: $ancestor" >&2
                exit 1
              fi
            done

            legacy="$HOME/.pi/agent/bin/pi"
            if [ -L "$legacy" ]; then
              target=$(${pkgs.coreutils}/bin/realpath -m -- "$legacy")
              local_source=$(${pkgs.coreutils}/bin/realpath -m -- "$HOME/dotfiles/.pi/agent/bin/pi")
              pinned_source=$(${pkgs.coreutils}/bin/realpath -m -- "${inputs.dotfiles}/.pi/agent/bin/pi")
              if [ "$target" != "$local_source" ] && [ "$target" != "$pinned_source" ]; then
                echo "Refusing unknown Pi launcher alias: $legacy -> $target" >&2
                exit 1
              fi
              $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -- "$legacy"
            elif [ -e "$legacy" ]; then
              echo "Refusing unknown Pi launcher at $legacy" >&2
              exit 1
            fi

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
      packages.pi-sandbox = mkLauncher pkgs;
      packages.pi-raw = mkPi pkgs;
      nix-unit.tests.piActivation = {
        testSecuresPiAgentDirectory = {
          expr = lib.hasInfix ''/bin/install -d -m 0700 "$HOME/.pi/agent"'' securePiAgentDirectory.data;
          expected = true;
        };
        testRetiresOnlyKnownPiAlias = {
          expr =
            lib.hasInfix ''/bin/rm -- "$legacy"'' securePiAgentDirectory.data
            && lib.hasInfix ''pinned_source=$('' securePiAgentDirectory.data
            && lib.hasInfix ''"$HOME/dotfiles/.pi/agent/bin/pi"'' securePiAgentDirectory.data
            && lib.hasInfix ''Refusing unknown Pi launcher'' securePiAgentDirectory.data;
          expected = true;
        };
        testRejectsSymlinkedAncestors = {
          expr = lib.hasInfix ''"$HOME/.pi/agent/bin"'' securePiAgentDirectory.data
            && lib.hasInfix ''if [ -L "$ancestor" ]'' securePiAgentDirectory.data;
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
