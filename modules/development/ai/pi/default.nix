{ config, inputs, lib, ... }:
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
          ./pi-install-esbuild.patch
          ./pi-streaming-json.patch
          ./pi-tool-preview-render.patch
          ./pi-markdown-streaming.patch
          ./pi-image-read.patch
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
            postInstall = (previous.postInstall or "") + ''
              # Runtime dependencies arrive after source patching; patch only the installed copy.
              lock_target="$out/lib/pi/node_modules/proper-lockfile/lib/mtime-precision.js"
              echo "eb5adf91a21715b50f39438cdcda52043d551ccb5fe530681364c474c7206218  $lock_target" | sha256sum --check --strict
              chmod u+w "$lock_target"
              patch --batch --fuzz=0 -d "$out/lib/pi" -p1 < ${./proper-lockfile-4.1.2.patch}
              echo "69ff3da4c35612d691c4e224d22e4128418be3caeabb682ab1ddf963784fb89d  $lock_target" | sha256sum --check --strict

              # Match llm-agents.nix's explicit defaults for the wrapped CLI.
              wrapProgram "$out/bin/pi" \
                --set PI_SKIP_VERSION_CHECK 1 \
                --set PI_TELEMETRY 0
            '';
            postInstallCheck = (previous.postInstallCheck or "") + ''
              package="$out/lib/pi/node_modules/@earendil-works/pi-coding-agent"
              PI_TEST_PACKAGE="$package" PI_TEST_BINARY="$out/bin/pi" ${pkgs.nodejs_22}/bin/node --test \
                ${./__tests__/proper-lockfile.test.mjs} \
                ${./__tests__/auth-startup.test.mjs} \
                ${./__tests__/codemode-worker.test.mjs} \
                ${./__tests__/mcp-background.test.mjs} \
                ${./__tests__/streaming-json.test.mjs} \
                ${./__tests__/tool-preview-render.test.mjs} \
                ${./__tests__/markdown-streaming.test.mjs} \
                ${./__tests__/tool-search-ranking.test.mjs} \
                ${./__tests__/image-read.test.mjs}
            '';
          }
      );
    in
    pi;
  mkIpcManifest = pkgs: pkgs.writeText "pi-ipc-capabilities.json" (builtins.toJSON config.piIpcRegistry);
  mkIpcRuntime = pkgs: pkgs.importNpmLock.buildNodeModules {
    npmRoot = ../nono;
    inherit (pkgs) nodejs;
    derivationArgs = {
      pname = "pi-ipc-runtime";
      postInstall = ''
        cp -r ${../nono/scripts} "$out/scripts"
        cp -r ${../nono/__tests__} "$out/__tests__"
      '';
      meta.description = "Pi IPC capability registry and bounded transport runtime";
    };
  };
  mkLauncher =
    pkgs: rawPi: { ipcRestricted ? false, proxyTestNono ? pkgs.nono }:
      assert pkgs.lib.assertMsg (pkgs.lib.versionAtLeast pkgs.nono.version "0.80.0")
        "Pi standalone credential proxy and sandbox protection require nono >= 0.80.0";
      let
        runtime = mkIpcRuntime pkgs;
        manifest = mkIpcManifest pkgs;
        # The desktop broker runs these from fixed store paths, never from the session PATH.
        desktopTools = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
          "--set PI_DESKTOP_WL_COPY ${pkgs.wl-clipboard}/bin/wl-copy --set PI_DESKTOP_GRIM ${pkgs.grim}/bin/grim --set PI_DESKTOP_PATH ${pkgs.coreutils}/bin";
        profile = pkgs.writeText "pi-nono-profile.json" (
          builtins.toJSON (config.flake.lib.mkPiCredentialProfile { inherit pkgs ipcRestricted; })
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
          ln -s ${../nono/scripts/pi-ask.lua} "$out/share/pi/pi-ask.lua"
          # A binary entry avoids sourcing BASH_ENV before nono applies confinement.
          ${pkgs.nodejs}/bin/node --input-type=module -e 'import { loadCapabilities } from "${runtime}/scripts/ipc-policy.mjs"; loadCapabilities(process.argv[1]);' "${manifest}"
          makeBinaryWrapper ${pkgs.nodejs}/bin/node "$out/bin/pi" \
            --unset NODE_OPTIONS --unset NODE_PATH \
            --set PI_IPC_MANIFEST "${manifest}" ${desktopTools} \
            --set PI_SSH_ADD ${pkgs.openssh}/bin/ssh-add \
            --prefix PATH : "$out/bin" \
            --add-flags "${runtime}/scripts/launcher.mjs ${pkgs.nono}/bin/nono ${rawPi}/bin/pi ${profile} ${pkgs.direnv}/bin/direnv ${pkgs.coreutils}/bin/env"
          makeBinaryWrapper ${pkgs.nodejs}/bin/node "$out/bin/pi-desktop" \
            --unset NODE_OPTIONS --unset NODE_PATH ${desktopTools} \
            --add-flags "${runtime}/scripts/pi-desktop.mjs"
          HERDR_REPORTER_TEST_SOURCE="${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts" \
            HERDR_READ_TEST_BINARY="${lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default}" \
            NONO_TEST_IPC_MODE="${if ipcRestricted then "pathname" else "off"}" \
          PI_TEST_BINARY="$out/bin/pi" PI_TEST_DIRENV="${pkgs.direnv}/bin/direnv" \
            NONO_PROXY_TEST_BINARY="${proxyTestNono}/bin/nono" NONO_TEST_PROFILE="${profile}" \
            GIT_TEST_BINARY="${pkgs.git}/bin/git" ENV_TEST_BINARY="${pkgs.coreutils}/bin/env" ${pkgs.nodejs}/bin/node --test \
            ${runtime}/__tests__/credential-filesystem.test.mjs \
            ${runtime}/__tests__/credentials.test.mjs \
            ${runtime}/__tests__/context7-auth.test.mjs \
            ${runtime}/__tests__/credential-proxy.test.mjs \
            ${runtime}/__tests__/desktop-broker.test.mjs \
            ${runtime}/__tests__/github-auth.test.mjs \
            ${runtime}/__tests__/direnv-bootstrap.test.mjs \
            ${runtime}/__tests__/git-worktree.test.mjs \
            ${runtime}/__tests__/herdr-launch.test.mjs \
            ${runtime}/__tests__/herdr-socket.test.mjs \
            ${runtime}/__tests__/herdr-reporting.test.mjs \
            ${runtime}/__tests__/herdr-reading.test.mjs \
            ${runtime}/__tests__/service-ipc.test.mjs \
            ${runtime}/__tests__/ipc-workflows.test.mjs \
            ${runtime}/__tests__/launcher.test.mjs \
            ${runtime}/__tests__/macos-browser-startup.test.mjs \
            ${runtime}/__tests__/reference-access.test.mjs \
            ${runtime}/__tests__/shell-protection.test.mjs \
            ${runtime}/__tests__/ssh-access.test.mjs \
            ${runtime}/__tests__/socket-isolation.test.mjs
        '';
  systemPackages = { pkgs, ... }: {
    environment = {
      systemPackages = [ (mkLauncher pkgs (mkPi pkgs) { }) ];
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
  options.piIpcRegistry = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = builtins.fromJSON (builtins.readFile ../nono/scripts/ipc-capabilities.json);
    description = "Nix-owned IPC capability catalog and profile selections; validated by the runtime JSON Schema.";
  };

  config = {
    flake.modules = {
      nixos.development.imports = [ systemPackages ];
      darwin.development.imports = [ systemPackages ];
      homeManager.development = homeManagerPi;
    };

    perSystem =
      { lib, pkgs, ... }:
      let
        launcher = mkLauncher pkgs (mkPi pkgs) { };
        evaluateSystem =
          if pkgs.stdenv.hostPlatform.isDarwin then
            inputs.nix-darwin.lib.darwinSystem
          else
            inputs.nixpkgs.lib.nixosSystem;
        profileConfig = evaluateSystem {
          system = pkgs.stdenv.hostPlatform.system;
          modules = [
            systemPackages
            { nixpkgs.pkgs = pkgs; }
          ];
        };
        launcherProfile = pkgs.buildEnv {
          name = "pi-profile-check";
          paths = [ launcher ];
          inherit (profileConfig.config.environment) pathsToLink;
        };
        # Upstream src is the dependency-lock directory; probe the installed helper.
        shellProbe = pkgs.writeShellScriptBin "pi" ''
          exec ${pkgs.nodejs}/bin/node ${../nono/__tests__/fixtures/shell-path-probe.mjs} \
            ${mkPi pkgs}/lib/pi/node_modules/@earendil-works/pi-coding-agent/dist/utils/shell.js ${pkgs.bash}/bin/bash "$@"
        '';
        # Routing checks exercise the assembled wrapper without host CA/keychain changes.
        routingNono = pkgs.runCommand "nono-routing-fixture"
          { inherit (pkgs.nono) version; }
          ''
            mkdir -p "$out/bin"
            ${pkgs.nodejs}/bin/node --input-type=module - "$out/bin/nono" <<'JS'
            import { writeFileSync } from "node:fs";
            import { proxyFixtureSource } from ${builtins.toJSON "${../nono/__tests__/fixtures/credential-proxy.mjs}"};
            writeFileSync(process.argv[2], "#!${pkgs.nodejs}/bin/node\n" + proxyFixtureSource(), { mode: 0o755 });
            JS
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
        # Match the central by-name export's priority without weakening its package policy.
        packages = lib.mkForce {
          pi-sandbox = launcher;
          pi-raw = mkPi pkgs;
          # Candidate only: Linux and desktop workflow gates must pass before default rollout.
          pi-ipc-candidate = mkLauncher pkgs (mkPi pkgs) { ipcRestricted = true; };
          pi-ipc-runtime = mkIpcRuntime pkgs;
        };
        checks.pi-launcher-routing =
          pkgs.runCommand "pi-launcher-routing"
            {
              PI_TEST_PROFILE = launcherProfile;
              # Native proxy smoke tests need real Nono, not the launcher-routing stub.
              PI_TEST_PROBE = "${mkLauncher (pkgs // { nono = routingNono; }) shellProbe { proxyTestNono = pkgs.nono; }}/bin/pi";
              PI_TEST_FISH = "${pkgs.fish}/bin/fish";
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${../nono/__tests__/routing.test.mjs}
              touch "$out"
            '';
        checks.pi-ipc =
          pkgs.runCommand "pi-ipc-check"
            {
              HERDR_REPORTER_TEST_SOURCE = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
              HERDR_READ_TEST_BINARY = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
              ENV_TEST_BINARY = "${pkgs.coreutils}/bin/env";
            }
            ''
              ${pkgs.nodejs}/bin/node --input-type=module -e 'import { loadCapabilities } from "${mkIpcRuntime pkgs}/scripts/ipc-policy.mjs"; loadCapabilities(process.argv[1]);' "${mkIpcManifest pkgs}"
              ${pkgs.nodejs}/bin/node --test \
                ${mkIpcRuntime pkgs}/__tests__/ipc-policy.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/json-lines-server.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/ipc-bootstrap.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/ipc-session.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/herdr-reporting.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/herdr-reading.test.mjs \
                ${mkIpcRuntime pkgs}/__tests__/desktop-broker.test.mjs
              touch "$out"
            '';
        nix-unit.tests.piIpc = {
          testOrdinaryFsmonitorUsesExistingDarwinEndpoints = {
            expr = config.piIpcRegistry.profiles.ordinary."git-fsmonitor";
            expected = { access = "connect-existing"; platforms = [ "darwin" ]; };
          };
          testRestrictedFsmonitorDeclaresFullProtocolAuthority = {
            expr = config.piIpcRegistry.capabilities."git-fsmonitor".authority;
            expected = "full-protocol";
          };
          testRestrictedFsmonitorPermitsLazyEndpointCreation = {
            expr = config.piIpcRegistry.profiles.restricted."git-fsmonitor".access;
            expected = "bind";
          };
        };
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
  };
}
