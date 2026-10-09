{ inputs, ... }:
let
  mkPi =
    pkgs:
    let
      system = pkgs.stdenv.hostPlatform.system;
      source = pkgs.applyPatches {
        name = "pi-source-with-local-overlays";
        src = inputs.pi;
        patches = [
          ./pi-selector-overlays.patch
          ./pi-auth-startup.patch
          ./pi-tool-search-ranking.patch
          ./pi-mcp-background.patch
        ];
        patchFlags = [
          "--batch"
          "--forward"
          "--fuzz=0"
          "-p1"
        ];
      };
      upstreamPi = inputs.pi.packages.${system}.default.override { inherit source; };
      pi = upstreamPi.overrideAttrs (
        previous:
          assert pkgs.lib.assertMsg
            (pkgs.lib.hasInfix "/bin/node" (
              previous.installPhase or ""
            )) "Review Pi Node runtime installation: upstream's package entry changed";
          assert pkgs.lib.assertMsg
            (pkgs.lib.hasInfix "dist/bundle/cli.js" (
              previous.installPhase or ""
            )) "Review Pi Node CLI packaging: upstream's bundle entry changed";
          {
            # Match llm-agents.nix's explicit defaults for the wrapped CLI.
            postInstall = (previous.postInstall or "") + ''
              wrapProgram "$out/bin/pi" \
                --set PI_SKIP_VERSION_CHECK 1 \
                --set PI_TELEMETRY 0
            '';
            postInstallCheck = (previous.postInstallCheck or "") + ''
              package="$out/lib/pi/node_modules/@earendil-works/pi-coding-agent"
              PI_TEST_PACKAGE="$package" PI_TEST_BINARY="$out/bin/pi" ${pkgs.nodejs_22}/bin/node --test \
                ${./__tests__/auth-startup.test.mjs} \
                ${./__tests__/codemode-worker.test.mjs} \
                ${./__tests__/mcp-background.test.mjs} \
                ${./__tests__/tool-search-ranking.test.mjs}
            '';
          }
      );
    in
    pi;
  mkLauncher = pkgs: rawPi:
    assert pkgs.lib.assertMsg
      (!pkgs.stdenv.hostPlatform.isDarwin || pkgs.lib.versionAtLeast pkgs.nono.version "0.79.0")
      "Pi shell startup protection requires nono >= 0.79.0 on macOS";
    let
      profile = pkgs.writeText "pi-nono-profile.json" (
        builtins.toJSON (builtins.fromJSON (builtins.readFile ../nono/scripts/profile.json))
      );
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
          --prefix PATH : "$out/bin" \
          --add-flags "${../nono/scripts}/launcher.mjs ${pkgs.nono}/bin/nono ${rawPi}/bin/pi ${profile}"
        PI_TEST_BINARY="$out/bin/pi" ${pkgs.nodejs}/bin/node --test \
          ${../nono}/__tests__/launcher.test.mjs \
          ${../nono}/__tests__/reference-access.test.mjs \
          ${../nono}/__tests__/shell-protection.test.mjs
      '';
  systemPackages = { pkgs, ... }: {
    environment = {
      systemPackages = [ (mkLauncher pkgs (mkPi pkgs)) ];
      pathsToLink = [ "/share/pi" ];
    };
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
      launcher = mkLauncher pkgs (mkPi pkgs);
      evaluateSystem =
        if pkgs.stdenv.hostPlatform.isDarwin then inputs.nix-darwin.lib.darwinSystem
        else inputs.nixpkgs.lib.nixosSystem;
      profileConfig = evaluateSystem {
        system = pkgs.stdenv.hostPlatform.system;
        modules = [ systemPackages { nixpkgs.pkgs = pkgs; } ];
      };
      launcherProfile = pkgs.buildEnv {
        name = "pi-profile-check";
        paths = [ launcher ];
        inherit (profileConfig.config.environment) pathsToLink;
      };
      shellProbe = pkgs.writeShellScriptBin "pi" ''
        exec ${pkgs.nodejs}/bin/node ${../nono/__tests__/fixtures/shell-path-probe.mjs} \
          ${(mkPi pkgs).src}/dist/utils/shell.js ${pkgs.bash}/bin/bash "$@"
      '';
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
      packages.pi-sandbox = launcher;
      packages.pi-raw = mkPi pkgs;
      checks.pi-launcher-routing = pkgs.runCommand "pi-launcher-routing"
        {
          PI_TEST_PROFILE = launcherProfile;
          PI_TEST_PROBE = "${mkLauncher pkgs shellProbe}/bin/pi";
          PI_TEST_FISH = "${pkgs.fish}/bin/fish";
        }
        ''
          ${pkgs.nodejs}/bin/node --test ${../nono/__tests__/routing.test.mjs}
          touch "$out"
        '';
      nix-unit.tests.piActivation = {
        testSecuresPiAgentDirectory = {
          expr = lib.hasInfix ''/bin/install -d -m 0700 "$HOME/.pi/agent"'' securePiAgentDirectory.data;
          expected = true;
        };
        testRetiresOnlyKnownPiAlias = {
          expr =
            lib.hasInfix ''/bin/rm -- "$legacy"'' securePiAgentDirectory.data
            && lib.hasInfix "pinned_source=$(" securePiAgentDirectory.data
            && lib.hasInfix ''"$HOME/dotfiles/.pi/agent/bin/pi"'' securePiAgentDirectory.data
            && lib.hasInfix "Refusing unknown Pi launcher" securePiAgentDirectory.data;
          expected = true;
        };
        testRejectsSymlinkedAncestors = {
          expr =
            lib.hasInfix ''"$HOME/.pi/agent/bin"'' securePiAgentDirectory.data
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
