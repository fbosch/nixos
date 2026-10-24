let
  piProfile = pkgs:
    let
      profile = builtins.fromJSON (builtins.readFile ./scripts/profile.json);
      github = profile.credential_capture.github;
    in
    profile // {
      credential_capture = profile.credential_capture // {
        github = github // {
          command = [ "${pkgs.gh}/bin/gh" ] ++ builtins.tail github.command;
        };
      };
    };
  nixBuildAssertions =
    { config, lib, ... }:
    {
      assertions = [
        {
          assertion = config.nix.enable && config.nix.daemon.enable && config.nix.daemonUser == "root";
          message = "Pi build access requires the root-owned multi-user Nix store.";
        }
        {
          assertion = lib.all (user: user == "root") config.nix.settings.trusted-users;
          message = "Pi's Nix socket access requires trusted-users to contain only root.";
        }
        {
          assertion =
            config.nix.settings.sandbox == true
            && !(config.nix.settings.sandbox-fallback or true)
            && config.nix.nrBuildUsers > 0;
          message = "Pi builds require sandboxing without fallback and dedicated unprivileged build users.";
        }
      ];
    };
  systemConfiguration =
    { pkgs, ... }:
    {
      environment = {
        systemPackages = [ pkgs.nono pkgs.gh ];
        etc."nono/pi.json".source = pkgs.writeText "pi-nono-profile.json" (builtins.toJSON (piProfile pkgs));
      };
    };
in
{
  flake.modules = {
    nixos.development.imports = [
      systemConfiguration
      nixBuildAssertions
    ];
    darwin.development.imports = [ systemConfiguration ];
  };

  perSystem =
    { lib, pkgs, ... }:
    let
      evaluated = systemConfiguration { inherit pkgs; };
      profile = builtins.fromJSON (
        builtins.unsafeDiscardStringContext evaluated.environment.etc."nono/pi.json".source.text
      );
    in
    {
      # Desktop and development services need pathname socket access. Filesystem
      # confinement does not constrain actions delegated to those services.
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nono-pi-ssh-access =
          pkgs.runCommand "nono-pi-ssh-access"
            {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              ENV_TEST_BINARY = "${pkgs.coreutils}/bin/env";
              SSH_KEYGEN_TEST_BINARY = lib.getExe' pkgs.openssh "ssh-keygen";
              SSH_ADD_TEST_BINARY = lib.getExe' pkgs.openssh "ssh-add";
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./.}/__tests__/ssh-access.test.mjs
              touch "$out"
            '';
        nono-pi-git-worktree =
          pkgs.runCommand "nono-pi-git-worktree"
            {
              nativeBuildInputs = [ pkgs.git ];
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              ENV_TEST_BINARY = "${pkgs.coreutils}/bin/env";
              GIT_TEST_BINARY = lib.getExe pkgs.git;
              WT_TEST_BINARY = "${pkgs.worktrunk}/bin/wt";
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./.}/__tests__/git-worktree.test.mjs
              touch "$out"
            '';
        nono-pi-github-access =
          pkgs.runCommand "nono-pi-github-access"
            {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              ENV_TEST_BINARY = "${pkgs.coreutils}/bin/env";
              NONO_TEST_PROFILE = evaluated.environment.etc."nono/pi.json".source;
              GH_TEST_BINARY = lib.getExe pkgs.gh;
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./.}/__tests__/github-access.test.mjs
              touch "$out"
            '';
        nono-pi-azure-access =
          pkgs.runCommand "nono-pi-azure-access"
            {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              NONO_TEST_PROFILE = evaluated.environment.etc."nono/pi.json".source;
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./__tests__}/azure-access.test.mjs
              touch "$out"
            '';
        nono-pi-socket-isolation =
          pkgs.runCommand "nono-pi-socket-isolation"
            {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
              NONO_TEST_PROFILE = evaluated.environment.etc."nono/pi.json".source;
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./__tests__}/socket-isolation.test.mjs
              touch "$out"
            '';
        nono-pi-nix-build-access = pkgs.testers.runNixOSTest {
          name = "nono-pi-nix-build-access";
          nodes.machine = {
            imports = [
              systemConfiguration
              nixBuildAssertions
            ];
            nix.package = pkgs.nix;
            nix.settings = {
              experimental-features = [
                "nix-command"
                "flakes"
              ];
              trusted-users = [ "root" ];
              allowed-users = [
                "root"
                "@wheel"
              ];
              substituters = lib.mkForce [ ];
              sandbox = true;
              sandbox-fallback = false;
            };
            users.users.tester = {
              isNormalUser = true;
              extraGroups = [ "wheel" ];
              password = "";
            };
            security.sudo.wheelNeedsPassword = false;
            system.switch.enable = true;
            system.activationScripts.pi-build-canary.text = "${pkgs.coreutils}/bin/touch /run/pi-system-activation";
            environment.systemPackages = [ pkgs.nodejs ];
            environment.etc = {
              "pi-host-only-marker".text = "This world-readable file is not a build input.";
              "pi-nix-build-probe.mjs".source = ./__tests__/fixtures/nix-build-probe.mjs;
              "pi-build-test.nix".text =
                let
                  builder = pkgs.writeText "pi-build-test.sh" ''
                    test "$EUID" -ne 0
                    test ! -e /etc/pi-host-only-marker
                    nnp=
                    while read -r key value rest; do
                      if [ "$key" = "NoNewPrivs:" ]; then nnp="$value"; fi
                    done < /proc/self/status
                    test "$nnp" = 1
                    printf 'built-without-host-authority\n' > "$out"
                  '';
                in
                ''
                  { name, noChroot ? false }:
                  let
                    bash = builtins.storePath "${pkgs.bash}";
                    script = builtins.storePath "${builder}";
                  in builtins.derivation {
                    inherit name;
                    system = "${pkgs.stdenv.hostPlatform.system}";
                    builder = bash + "/bin/bash";
                    args = [ "-eu" script ];
                    __noChroot = noChroot;
                  }
                '';
            };
            virtualisation.memorySize = 2048;
          };
          testScript = builtins.readFile ./__tests__/nix-build-access.py;
        };
      };
      nix-unit.tests.nonoProfile = {
        testInstallsNonoAndGithubCli = {
          expr = map lib.getName evaluated.environment.systemPackages;
          expected = [ "nono" "gh" ];
        };
        testUsesSystemOwnedProfile = {
          expr = builtins.attrNames evaluated.environment.etc;
          expected = [ "nono/pi.json" ];
        };
        testKeepsDefaultAndRuntimeGroups = {
          expr = {
            inherit (profile) extends groups;
          };
          expected = {
            extends = "default";
            groups.include = [
              "node_runtime"
              "rust_runtime"
              "python_runtime"
              {
                name = "user_caches_macos";
                when = "macos";
              }
              {
                name = "user_caches_linux";
                when = "linux";
              }
              {
                name = "linux_sysfs_read";
                when = "linux";
              }
              "nix_runtime"
              "git_config"
              "unlink_protection"
            ];
          };
        };
        testPreservesExistingAccess = {
          expr = {
            inherit (profile) filesystem network workdir;
          };
          expected = {
            filesystem = {
              allow = [
                "$HOME/.pi"
                "$HOME/.npm/_cacache"
                "$HOME/.npm/_logs"
                "$HOME/.azure"
                "$HOME/.azure-devops/python-sdk/cache"
                {
                  path = "/dev/dri";
                  when = "linux";
                }
              ];
              read = [
                "$HOME/.agents/skills"
                "$HOME/.local/share/gh/extensions"
                "$HOME/.local/state/pnpm-globals/current/node_modules"
                "$HOME/.nvm"
                "/tmp"
                "$TMPDIR"
              ];
              bypass_protection = [ "$HOME/.azure" ];
              unix_socket = [
                {
                  path = "/nix/var/nix/daemon-socket/socket";
                  when = "linux";
                }
              ];
              suppress_save_prompt = [ "/" ];
            };
            network = {
              block = false;
              open_port = [ 9222 2828 ];
              credentials = [ "github" ];
              custom_credentials.github = {
                upstream = "https://api.github.com";
                credential_key = "cmd://github";
                env_var = "GH_TOKEN";
              };
            };
            workdir.access = "readwrite";
          };
        };
        testCapturesGithubWithPackagedCli = {
          expr = profile.credential_capture.github;
          expected = {
            command = [ "${pkgs.gh}/bin/gh" "auth" "token" "--hostname" "github.com" ];
            timeout_secs = 10;
            cache_ttl_secs = 300;
          };
        };
        testKeepsSocketCompatibilityAndLandlockNetworkPolicy = {
          expr = profile.linux;
          expected = {
            af_unix_mediation = "off";
            sandbox_policy = "landlock";
          };
        };
        testKeepsSignalIsolationAndDisablesElevation = {
          expr = profile.security;
          expected = {
            signal_mode = "isolated";
            capability_elevation = false;
          };
        };
        # Chromium's power monitor needs RootDomainUserClient; its children exchange
        # ports through bundle-specific, PID-suffixed Mach rendezvous services.
        testKeepsMacosRuntimeRulesScoped = {
          expr = profile.unsafe_macos_seatbelt_rules;
          expected = [
            ''(allow network-outbound (remote tcp "*:22"))''
            ''(allow network-outbound (remote tcp "localhost:*"))''
            "(allow ipc-sysv-sem)"
            "(allow lsopen)"
            ''(allow iokit-open (iokit-user-client-class "RootDomainUserClient"))''
            ''(allow mach-register (global-name-regex #"^(org[.]chromium[.]Chromium|com[.]google[.]Chrome|com[.]google[.]chrome[.]for[.]testing)[.]MachPortRendezvousServer[.][0-9]+$"))''
          ];
        };
        testAllowsImageViewerLaunchServices = {
          expr = builtins.elem "(allow lsopen)" profile.unsafe_macos_seatbelt_rules;
          expected = true;
        };
      };
    };
}
