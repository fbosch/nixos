let
  piProfile = builtins.fromJSON (builtins.readFile ./scripts/profile.json);
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
        systemPackages = [ pkgs.nono ];
        etc."nono/pi.json".source = pkgs.writeText "pi-nono-profile.json" (builtins.toJSON piProfile);
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
      profile = builtins.fromJSON evaluated.environment.etc."nono/pi.json".source.text;
    in
    {
      # Desktop and development services need pathname socket access. Filesystem
      # confinement does not constrain actions delegated to those services.
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nono-pi-ssh-access =
          pkgs.runCommand "nono-pi-ssh-access"
            {
              NONO_TEST_BINARY = lib.getExe pkgs.nono;
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
              GIT_TEST_BINARY = lib.getExe pkgs.git;
              WT_TEST_BINARY = "${pkgs.worktrunk}/bin/wt";
            }
            ''
              ${pkgs.nodejs}/bin/node --test ${./.}/__tests__/git-worktree.test.mjs
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
        testInstallsNono = {
          expr = map lib.getName evaluated.environment.systemPackages;
          expected = [ "nono" ];
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
                {
                  path = "/dev/dri";
                  when = "linux";
                }
              ];
              read = [
                "$HOME/.agents/skills"
                "$HOME/.nvm"
                "$HOME/.config"
                "/tmp"
                "$TMPDIR"
              ];
              unix_socket = [
                {
                  path = "/nix/var/nix/daemon-socket/socket";
                  when = "linux";
                }
              ];
              suppress_save_prompt = [ "/" ];
            };
            network.block = false;
            workdir.access = "readwrite";
          };
        };
        testKeepsSocketCompatibility = {
          expr = profile.linux;
          expected.af_unix_mediation = "off";
        };
        testKeepsSignalIsolationAndDisablesElevation = {
          expr = profile.security;
          expected = {
            signal_mode = "isolated";
            capability_elevation = false;
          };
        };
        testKeepsMacosLmdbSupport = {
          expr = profile.unsafe_macos_seatbelt_rules;
          expected = [ "(allow ipc-sysv-sem)" ];
        };
      };
    };
}
