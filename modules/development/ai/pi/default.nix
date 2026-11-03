{ config, inputs, lib, ... }:
let
  mkPi =
    pkgs:
    let
      source = pkgs.applyPatches {
        name = "pi-source-with-local-overlays";
        src = inputs.pi;
        patches = [
          ./pi-copilot-catalog-types.patch
          ./pi-selector-overlays.patch
          ./pi-auth-startup.patch
          ./pi-tool-search-ranking.patch
          ./pi-mcp-background.patch
          ./pi-install-esbuild.patch
          ./pi-runtime-locks.patch
          ./pi-streaming-json.patch
          ./pi-tool-preview-render.patch
          ./pi-markdown-streaming.patch
          ./pi-image-read.patch
          ./pi-model-executor.patch
        ];
        patchFlags = [
          "--batch"
          "--forward"
          "--fuzz=0"
          "-p1"
        ];
      };
      # Evaluate the patched builder so every pinned Pi workspace is supplied locally.
      upstreamPi = pkgs.callPackage (source + "/nix/package.nix") { inherit source; };
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
              runtime_lock_target="$out/lib/pi/node_modules/proper-lockfile/lib/lockfile.js"
              echo "c517a976f7a31c8b1768cb8e7ac9936aee70299ae762548495016a79d64a6434  $runtime_lock_target" | sha256sum --check --strict
              chmod u+w "$runtime_lock_target"
              patch --batch --fuzz=0 -d "$out/lib/pi" -p1 < ${./proper-lockfile-4.1.2.patch}
              echo "69ff3da4c35612d691c4e224d22e4128418be3caeabb682ab1ddf963784fb89d  $lock_target" | sha256sum --check --strict

              # Match llm-agents.nix's explicit defaults for the wrapped CLI.
              wrapProgram "$out/bin/pi" \
                --set PI_SKIP_VERSION_CHECK 1 \
                --set PI_TELEMETRY 0
            '';
            postInstallCheck = (previous.postInstallCheck or "") + ''
              package="$out/lib/pi/node_modules/@earendil-works/pi-coding-agent"
              PI_TEST_PACKAGE="$package" PI_TEST_BINARY="$out/bin/pi" ${pkgs.nodejs_22}/bin/node --test "${./__tests__}/*.test.mjs"
            '';
          }
      );
    in
    pi;
  mkIpcManifest = pkgs: pkgs.writeText "pi-ipc-capabilities.json" (builtins.toJSON config.pi.sandbox.ipc.registry);
  mkSandboxPolicy = pkgs: pkgs.writeText "pi-sandbox-policy.json" (builtins.toJSON config.pi.sandbox.launcherPolicy);
  # The runtime holds no development packages: Node strips .mts types itself. `withTypes` adds only
  # @types/node for the type check, which uses pkgs.typescript_7 instead of npm's per-platform binaries.
  mkIpcRuntime = pkgs: { withTypes ? false }:
    let
      package = lib.importJSON ../nono/package.json;
      packageLock = lib.importJSON ../nono/package-lock.json;
      typeModules = [ "node_modules/@types/node" "node_modules/undici-types" ];
      keep = path: module: !(module.dev or false) || (withTypes && builtins.elem path typeModules);
      devDependencies = lib.optionalAttrs withTypes {
        devDependencies."@types/node" = package.devDependencies."@types/node";
      };
    in
    pkgs.importNpmLock.buildNodeModules {
      npmRoot = ../nono;
      inherit (pkgs) nodejs;
      package = removeAttrs package [ "devDependencies" ] // devDependencies;
      packageLock = packageLock // {
        packages = lib.filterAttrs keep packageLock.packages // {
          "" = removeAttrs packageLock.packages."" [ "devDependencies" ] // devDependencies;
        };
      };
      derivationArgs = {
        pname = if withTypes then "pi-ipc-typecheck" else "pi-ipc-runtime";
        postInstall = ''
          cp -r ${../nono/scripts} "$out/scripts"
          cp -r ${../nono/__tests__} "$out/__tests__"
        '';
        meta.description = "Pi IPC capability registry and bounded transport runtime";
      };
    };
  mkLauncher =
    pkgs: rawPi: { ipcRestricted ? true, proxyTestNono ? pkgs.nono, executorPi ? rawPi }:
      assert pkgs.lib.assertMsg (pkgs.lib.versionAtLeast pkgs.nono.version "0.80.0")
        "Pi standalone credential proxy and sandbox protection require nono >= 0.80.0";
      let
        runtime = mkIpcRuntime pkgs { };
        manifest = mkIpcManifest pkgs;
        sandboxPolicy = mkSandboxPolicy pkgs;
        # The desktop broker runs these from fixed store paths, never from the session PATH.
        desktopTools = pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux
          "--set PI_DESKTOP_WL_COPY ${pkgs.wl-clipboard}/bin/wl-copy --set PI_DESKTOP_GRIM ${pkgs.grim}/bin/grim --set PI_DESKTOP_IMAGE_VIEWER ${pkgs.loupe}/bin/loupe --set PI_DESKTOP_IMAGE_DATA ${pkgs.shared-mime-info}/share --set PI_DESKTOP_PATH ${pkgs.coreutils}/bin";
        # The executor trusts only the activated dotfiles revision of models.json: a sandboxed
        # configuration session can edit the working copy, which decides where credentials go.
        executorModelsSource = "${inputs.dotfiles}/.pi/agent/models.json";
        executorModelsFlag = pkgs.lib.optionalString (builtins.pathExists executorModelsSource)
          "--set PI_MODEL_EXECUTOR_MODELS ${builtins.path { path = executorModelsSource; name = "pi-executor-models.json"; }}";
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
          ${pkgs.nodejs}/bin/node --input-type=module -e 'import { loadCapabilities } from "${runtime}/scripts/ipc/policy.mts"; loadCapabilities(process.argv[1]);' "${manifest}"
          ${pkgs.nodejs}/bin/node --input-type=module -e 'import { loadSandboxPolicy } from "${runtime}/scripts/shared/sandbox-policy.mts"; loadSandboxPolicy(process.argv[1]);' "${sandboxPolicy}"
          makeBinaryWrapper ${pkgs.nodejs}/bin/node "$out/bin/pi" \
            --unset NODE_OPTIONS --unset NODE_PATH \
            --set PI_IPC_MANIFEST "${manifest}" --set PI_SANDBOX_POLICY "${sandboxPolicy}" ${desktopTools} \
            --set PI_NONO_DIAGNOSTICS 1 \
            --set PI_SSH_ADD ${pkgs.openssh}/bin/ssh-add \
            --set PI_MODEL_EXECUTOR_PACKAGE ${executorPi}/lib/pi/node_modules/@earendil-works/pi-coding-agent ${executorModelsFlag} \
            --prefix PATH : "$out/bin" \
            --add-flags "${runtime}/scripts/launcher.mts ${pkgs.nono}/bin/nono ${rawPi}/bin/pi ${profile} ${pkgs.direnv}/bin/direnv ${pkgs.coreutils}/bin/env"
          makeBinaryWrapper ${pkgs.nodejs}/bin/node "$out/bin/pi-desktop" \
            --unset NODE_OPTIONS --unset NODE_PATH ${desktopTools} \
            --add-flags "${runtime}/scripts/pi-desktop.mts"
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
        launcherProfileFile = pkgs.writeText "pi-nono-profile.json" (
          builtins.toJSON (config.flake.lib.mkPiCredentialProfile { inherit pkgs; ipcRestricted = true; })
        );
        ordinaryProfileFile = pkgs.writeText "pi-nono-profile.json" (
          builtins.toJSON (config.flake.lib.mkPiCredentialProfile { inherit pkgs; })
        );
        isLinux = pkgs.stdenv.hostPlatform.isLinux;
        # One `node --test` run over nono test files matching `tests`. TMPDIR moves out of /build:
        # the profile's TMPDIR read grant would otherwise cover nono state or mask fixture denials.
        # Native-kernel tests need NONO_TEST_BINARY, which Darwin Nix builders cannot use: they
        # reject restrictive Seatbelt profiles with EPERM, so macOS keeps the argument tests only.
        nonoSuite = name: { tests, profile, ipcMode }:
          pkgs.runCommand name
            ({
              nativeBuildInputs = lib.optional isLinux pkgs.git;
              NONO_TEST_PROFILE = profile;
              NONO_TEST_IPC_MODE = ipcMode;
              NONO_PROFILE_TEST_BINARY = lib.getExe pkgs.nono;
              NONO_PROXY_TEST_BINARY = lib.getExe pkgs.nono;
              PI_SANDBOX_POLICY = mkSandboxPolicy pkgs;
              PI_TEST_BINARY = "${launcher}/bin/pi";
              PI_RAW_TEST_BINARY = lib.getExe (mkPi pkgs);
              PI_TEST_DIRENV = "${pkgs.direnv}/bin/direnv";
              # The routing probe is a launcher whose nono is a stub; the shell probe stands in for
              # raw Pi, so the default model executor runs from the real Pi package.
              PI_TEST_PROFILE = launcherProfile;
              PI_TEST_PROBE = "${mkLauncher (pkgs // { nono = routingNono; }) shellProbe { proxyTestNono = pkgs.nono; executorPi = mkPi pkgs; }}/bin/pi";
              PI_TEST_FISH = "${pkgs.fish}/bin/fish";
              ENV_TEST_BINARY = "${pkgs.coreutils}/bin/env";
              CAT_TEST_BINARY = "${pkgs.coreutils}/bin/cat";
              BASH_TEST_BINARY = "${pkgs.bash}/bin/bash";
              CURL_TEST_BINARY = lib.getExe pkgs.curl;
              GIT_TEST_BINARY = lib.getExe pkgs.git;
              SSH_ADD_TEST_BINARY = lib.getExe' pkgs.openssh "ssh-add";
              HERDR_REPORTER_TEST_SOURCE = "${inputs.herdr}/src/integration/assets/pi/herdr-agent-state.ts";
              HERDR_READ_TEST_BINARY = lib.getExe inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.default;
            } // lib.optionalAttrs isLinux {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              SSH_KEYGEN_TEST_BINARY = lib.getExe' pkgs.openssh "ssh-keygen";
              GH_TEST_BINARY = lib.getExe pkgs.gh;
              WT_TEST_BINARY = "${pkgs.worktrunk}/bin/wt";
              GIO_TEST_BINARY = "${pkgs.glib.bin}/bin/gio";
              MIME_TEST_DATA = "${pkgs.shared-mime-info}/share";
              CLAUDE_TEST_BINARY = lib.getExe inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code;
            })
            ''
              # Some kernel tests need fixtures outside /tmp, below an existing HOME.
              mkdir tmp home
              export TMPDIR="$PWD/tmp" HOME="$PWD/home"
              ${pkgs.nodejs}/bin/node --test "${mkIpcRuntime pkgs { }}/__tests__/${tests}"
              touch "$out"
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
          pi-ipc-candidate = launcher;
          pi-ipc-runtime = mkIpcRuntime pkgs { };
        };
        checks = lib.mkMerge [
          {
            # Same compiler version as the npm devDependency used for local editing.
            nono-typecheck =
              pkgs.runCommand "nono-typecheck" { nativeBuildInputs = [ pkgs.typescript_7 ]; } ''
                cp -r ${mkIpcRuntime pkgs { withTypes = true; }}/. .
                cp ${../nono/tsconfig.json} tsconfig.json
                tsc -p .
                touch "$out"
              '';
            # Every nono test file against the shipped restricted profile. Tests skip themselves when
            # the tool they need is absent, so the environment below is the union of what they use.
            nono-tests = nonoSuite "nono-tests" {
              tests = "*.test.mjs";
              profile = launcherProfileFile;
              ipcMode = "pathname";
            };
            # The files whose policy depends on the profile, again with the ordinary (unrestricted IPC) profile.
            nono-tests-ordinary = nonoSuite "nono-tests-ordinary" {
              tests = "{github-access,azure-access,socket-isolation}.test.mjs";
              profile = ordinaryProfileFile;
              ipcMode = "off";
            };
          }
        ];
        nix-unit.tests.piIpc = {
          testDefaultLauncherUsesRestrictedIpc = {
            expr = launcher.outPath;
            expected = (mkLauncher pkgs (mkPi pkgs) { ipcRestricted = true; }).outPath;
          };
          testOrdinaryFsmonitorUsesExistingDarwinEndpoints = {
            expr = config.pi.sandbox.ipc.registry.profiles.ordinary."git-fsmonitor";
            expected = { access = "connect-existing"; platforms = [ "darwin" ]; };
          };
          testRestrictedFsmonitorDeclaresFullProtocolAuthority = {
            expr = config.pi.sandbox.ipc.registry.capabilities."git-fsmonitor".authority;
            expected = "full-protocol";
          };
          testRestrictedFsmonitorPermitsLazyEndpointCreation = {
            expr = config.pi.sandbox.ipc.registry.profiles.restricted."git-fsmonitor".access;
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
