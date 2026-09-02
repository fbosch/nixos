{ config, inputs, ... }:
let
  inherit (config.flake.meta.user) username;
  machineIdValidationScript = ''
    machine_id_path="''${1:-/sysroot/persist/etc/machine-id}"

    if [[ ! -f "$machine_id_path" || -L "$machine_id_path" ]]; then
      echo "Persistent machine ID must be a regular file: $machine_id_path" >&2
      exit 1
    fi

    machine_id="$(<"$machine_id_path")"
    machine_id_size="$(wc -c < "$machine_id_path")"
    if [[ "$machine_id_size" -ne 33 || ! "$machine_id" =~ ^[0-9a-f]{32}$ || "$machine_id" == "00000000000000000000000000000000" ]]; then
      echo "Persistent machine ID is empty or malformed: $machine_id_path" >&2
      exit 1
    fi
  '';
  preserveAt = {
    "/persist" = {
      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
          mode = "0444";
        }
        {
          file = "/var/lib/systemd/random-seed";
          how = "symlink";
          inInitrd = true;
          configureParent = true;
          mode = "0600";
        }
      ];

      directories = [
        {
          directory = "/var/lib/nixos";
          inInitrd = true;
          mode = "0755";
        }
        {
          directory = "/var/lib/systemd/timers";
          mode = "0755";
        }
        {
          directory = "/var/log";
          mode = "0755";
        }
        {
          directory = "/home/${username}";
          user = username;
          group = "users";
          mode = "0700";
        }
      ];
    };
  };
in
{
  flake.modules = {
    nixos."hosts/rvn-pc/preservation" =
      { lib, ... }:
      {
        imports = [
          inputs.preservation.nixosModules.preservation
          config.flake.modules.nixos.preservation
        ];

        boot.initrd.systemd = {
          enable = true;
          services.verify-persistent-machine-id = {
            description = "Verify restored persistent machine ID";
            requires = [ "sysroot-persist.mount" ];
            after = [
              "sysroot-persist.mount"
              "systemd-tmpfiles-setup-sysroot.service"
            ];
            before = [ "initrd-preservation.target" ];
            requiredBy = [ "initrd-preservation.target" ];
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
            script = machineIdValidationScript;
          };
        };

        fileSystems = {
          "/nix".neededForBoot = true;
          "/persist".neededForBoot = true;
        };

        preservation = {
          enable = true;
          inherit preserveAt;
        };

        systemd.suppressedSystemUnits = [ "systemd-machine-id-commit.service" ];

        sops.age = {
          keyFile = lib.mkForce "/persist/var/lib/sops-nix/key.txt";
          generateKey = lib.mkForce false;
        };

        services.openssh = {
          generateHostKeys = false;
          hostKeys = [
            {
              path = "/persist/etc/ssh/ssh_host_rsa_key";
              type = "rsa";
              bits = 4096;
            }
            {
              path = "/persist/etc/ssh/ssh_host_ed25519_key";
              type = "ed25519";
            }
          ];
        };
      };

    homeManager."hosts/rvn-pc/preservation" =
      { lib, ... }:
      {
        sops.age.generateKey = lib.mkForce false;
      };
  };

  perSystem =
    { lib
    , pkgs
    , system
    , ...
    }:
    let
      futureSystem = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          inputs.home-manager.nixosModules.home-manager
          config.flake.modules.nixos.users
          config.flake.modules.nixos.secrets
          config.flake.modules.nixos."system/networkmanager"
          config.flake.modules.nixos."services/attic"
          config.flake.modules.nixos."system/tiered-service-startup"
          config.flake.modules.nixos.vpn
          config.flake.modules.nixos."virtualization/libvirt"
          config.flake.modules.nixos."hosts/rvn-pc/login"
          config.flake.modules.nixos."hosts/rvn-pc/disko"
          config.flake.modules.nixos."hosts/rvn-pc/preservation"
          {
            system.stateVersion = "25.05";
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.${username}.imports = [
                config.flake.modules.homeManager.users
                config.flake.modules.homeManager.secrets
                config.flake.modules.homeManager."hosts/rvn-pc/preservation"
              ];
            };
          }
        ];
      };
      future = futureSystem.config;
      futureHome = future.home-manager.users.${username};
      state = future.preservation.preserveAt."/persist";
      initrdMounts = builtins.filter
        (
          mount: lib.elem "initrd-preservation.target" (mount.wantedBy or [ ])
        )
        future.boot.initrd.systemd.mounts;
      regularMounts = builtins.filter
        (
          mount: lib.elem "preservation.target" (mount.wantedBy or [ ])
        )
        future.systemd.mounts;
      mountPair = mount: "${mount.what} -> ${mount.where}";
      simplePath = value: {
        path = value.directory or value.file;
        inherit (value)
          how
          inInitrd
          mode
          user
          group
          ;
      };
      tmpfileSummary =
        settings: path: type:
        let
          rule = settings.${path}.${type};
        in
        "${rule.type} ${rule.mode} ${rule.user}:${rule.group} ${rule.argument}";
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        rvn-pc-machine-id =
          let
            validator = pkgs.writeShellScript "verify-persistent-machine-id" machineIdValidationScript;
          in
          pkgs.runCommand "rvn-pc-machine-id-check" { } ''
            fixtures="$TMPDIR/machine-id-fixtures"
            mkdir -p "$fixtures"

            expect_failure() {
              if ${validator} "$1"; then
                echo "Machine ID validation unexpectedly passed: $1" >&2
                exit 1
              fi
            }

            expect_failure "$fixtures/missing"

            : > "$fixtures/empty"
            expect_failure "$fixtures/empty"

            printf '%s\n' '0123456789abcdef0123456789abcde' > "$fixtures/short"
            expect_failure "$fixtures/short"

            printf '%s\n' '0123456789ABCDEF0123456789ABCDEF' > "$fixtures/uppercase"
            expect_failure "$fixtures/uppercase"

            printf '%s\n' '00000000000000000000000000000000' > "$fixtures/all-zero"
            expect_failure "$fixtures/all-zero"

            printf '%s\n' '0123456789abcdef0123456789abcdef' > "$fixtures/valid"
            ${validator} "$fixtures/valid"

            printf '\n' >> "$fixtures/valid"
            expect_failure "$fixtures/valid"

            printf '%s\n' '0123456789abcdef0123456789abcdef' > "$fixtures/valid"
            ln -s "$fixtures/valid" "$fixtures/symlink"
            expect_failure "$fixtures/symlink"

            touch "$out"
          '';
      };

      nix-unit.tests.rvnPcPreservation = lib.optionalAttrs (system == "x86_64-linux") {
        testEarlySystemState = {
          expr = {
            files = map simplePath state.files;
            directories = map simplePath (builtins.filter (value: value.inInitrd) state.directories);
          };
          expected = {
            files = [
              {
                path = "/etc/machine-id";
                how = "bindmount";
                inInitrd = true;
                mode = "0444";
                user = "root";
                group = "root";
              }
              {
                path = "/var/lib/systemd/random-seed";
                how = "symlink";
                inInitrd = true;
                mode = "0600";
                user = "root";
                group = "root";
              }
            ];
            directories = [
              {
                path = "/var/lib/nixos";
                how = "bindmount";
                inInitrd = true;
                mode = "0755";
                user = "root";
                group = "root";
              }
            ];
          };
        };

        testRegularSystemState = {
          expr = lib.sortOn (value: value.path) (
            map simplePath (builtins.filter (value: value.inInitrd == false) state.directories)
          );
          expected = [
            {
              path = "/etc/NetworkManager/system-connections";
              how = "bindmount";
              inInitrd = false;
              mode = "0700";
              user = "root";
              group = "root";
            }
            {
              path = "/etc/mullvad-vpn";
              how = "bindmount";
              inInitrd = false;
              mode = "0755";
              user = "root";
              group = "root";
            }
            {
              path = "/home/${username}";
              how = "bindmount";
              inInitrd = false;
              mode = "0700";
              user = username;
              group = "users";
            }
            {
              path = "/var/lib/NetworkManager";
              how = "bindmount";
              inInitrd = false;
              mode = "0755";
              user = "root";
              group = "root";
            }
            {
              path = "/var/lib/libvirt";
              how = "bindmount";
              inInitrd = false;
              mode = "0755";
              user = "root";
              group = "root";
            }
            {
              path = "/var/lib/private/attic-upload";
              how = "bindmount";
              inInitrd = false;
              mode = "0750";
              user = "root";
              group = "root";
            }
            {
              path = "/var/lib/swtpm-localca";
              how = "bindmount";
              inInitrd = false;
              mode = "0750";
              user = "root";
              group = "root";
            }
            {
              path = "/var/lib/systemd/timers";
              how = "bindmount";
              inInitrd = false;
              mode = "0755";
              user = "root";
              group = "root";
            }
            {
              path = "/var/lib/tailscale";
              how = "bindmount";
              inInitrd = false;
              mode = "0700";
              user = "root";
              group = "root";
            }
            {
              path = "/var/log";
              how = "bindmount";
              inInitrd = false;
              mode = "0755";
              user = "root";
              group = "root";
            }
          ];
        };

        testNoPerPathUserAllowlist = {
          expr = state.users;
          expected = { };
        };

        testIdentityPaths = {
          expr = {
            systemSops = {
              inherit (future.sops.age) keyFile generateKey;
            };
            homeSops = {
              inherit (futureHome.sops.age) keyFile generateKey;
            };
            sshGeneratesHostKeys = future.services.openssh.generateHostKeys;
            sshKeygenUnitPresent = future.systemd.services ? sshd-keygen;
            sshHostKeys = future.services.openssh.hostKeys;
          };
          expected = {
            systemSops = {
              keyFile = "/persist/var/lib/sops-nix/key.txt";
              generateKey = false;
            };
            homeSops = {
              keyFile = "/home/${username}/.config/sops/age/keys.txt";
              generateKey = false;
            };
            sshGeneratesHostKeys = false;
            sshKeygenUnitPresent = false;
            sshHostKeys = [
              {
                path = "/persist/etc/ssh/ssh_host_rsa_key";
                type = "rsa";
                bits = 4096;
              }
              {
                path = "/persist/etc/ssh/ssh_host_ed25519_key";
                type = "ed25519";
              }
            ];
          };
        };

        testBootContract = {
          expr = {
            initrdSystemd = future.boot.initrd.systemd.enable;
            nixNeededForBoot = future.fileSystems."/nix".neededForBoot;
            persistNeededForBoot = future.fileSystems."/persist".neededForBoot;
            machineIdCommitSuppressed = lib.elem "systemd-machine-id-commit.service" future.systemd.suppressedSystemUnits;
            account = {
              uid = future.users.users.${username}.uid;
              homeModeMatches =
                lib.removePrefix "0"
                  (
                    builtins.head (
                      map (value: value.mode) (
                        builtins.filter (value: (value.directory or null) == "/home/${username}") state.directories
                      )
                    )
                  ) == future.users.users.${username}.homeMode;
              mutableUsers = future.users.mutableUsers;
              passwordNeededForUsers = future.sops.secrets.user-password-hash.neededForUsers;
            };
            atticQueue = {
              inherit (future.systemd.services.attic-upload.serviceConfig) DynamicUser StateDirectory;
            };
            initrdTarget = {
              inherit (future.boot.initrd.systemd.targets.initrd-preservation) before wantedBy;
            };
            regularTarget = {
              inherit (future.systemd.targets.preservation) before wantedBy;
            };
            machineIdVerifier = {
              inherit (future.boot.initrd.systemd.services.verify-persistent-machine-id)
                after
                before
                requiredBy
                requires
                ;
            };
          };
          expected = {
            initrdSystemd = true;
            nixNeededForBoot = true;
            persistNeededForBoot = true;
            machineIdCommitSuppressed = true;
            account = {
              uid = 1000;
              homeModeMatches = true;
              mutableUsers = false;
              passwordNeededForUsers = true;
            };
            atticQueue = {
              DynamicUser = true;
              StateDirectory = "attic-upload";
            };
            initrdTarget = {
              before = [ "initrd.target" ];
              wantedBy = [ "initrd.target" ];
            };
            regularTarget = {
              before = [ "sysinit.target" ];
              wantedBy = [ "sysinit.target" ];
            };
            machineIdVerifier = {
              after = [
                "sysroot-persist.mount"
                "systemd-tmpfiles-setup-sysroot.service"
              ];
              before = [ "initrd-preservation.target" ];
              requiredBy = [ "initrd-preservation.target" ];
              requires = [ "sysroot-persist.mount" ];
            };
          };
        };

        testGeneratedMounts = {
          expr = {
            initrd = map mountPair initrdMounts;
            regular = builtins.sort builtins.lessThan (map mountPair regularMounts);
            initrdOrdering = lib.all
              (
                mount:
                lib.elem "initrd-preservation.target" mount.before
                && lib.elem "initrd-preservation.target" mount.wantedBy
                && lib.hasInfix "x-initrd.mount" mount.options
              )
              initrdMounts;
            regularOrdering = lib.all
              (
                mount:
                lib.elem "systemd-tmpfiles-setup.service" mount.before
                && lib.elem "preservation.target" mount.before
                && lib.elem "preservation.target" mount.wantedBy
              )
              regularMounts;
          };
          expected = {
            initrd = [
              "/sysroot/persist/var/lib/nixos -> /sysroot/var/lib/nixos"
              "/sysroot/persist/etc/machine-id -> /sysroot/etc/machine-id"
            ];
            regular = [
              "/persist/etc/NetworkManager/system-connections -> /etc/NetworkManager/system-connections"
              "/persist/etc/mullvad-vpn -> /etc/mullvad-vpn"
              "/persist/home/${username} -> /home/${username}"
              "/persist/var/lib/NetworkManager -> /var/lib/NetworkManager"
              "/persist/var/lib/libvirt -> /var/lib/libvirt"
              "/persist/var/lib/private/attic-upload -> /var/lib/private/attic-upload"
              "/persist/var/lib/swtpm-localca -> /var/lib/swtpm-localca"
              "/persist/var/lib/systemd/timers -> /var/lib/systemd/timers"
              "/persist/var/lib/tailscale -> /var/lib/tailscale"
              "/persist/var/log -> /var/log"
            ];
            initrdOrdering = true;
            regularOrdering = true;
          };
        };

        testGeneratedTmpfiles = {
          expr = {
            machineIdPersistent =
              tmpfileSummary future.boot.initrd.systemd.tmpfiles.settings.preservation
                "/sysroot/persist/etc/machine-id"
                "f";
            machineIdVolatile =
              tmpfileSummary future.boot.initrd.systemd.tmpfiles.settings.preservation "/sysroot/etc/machine-id"
                "f";
            randomSeedLink =
              tmpfileSummary future.boot.initrd.systemd.tmpfiles.settings.preservation
                "/sysroot/var/lib/systemd/random-seed"
                "L";
            randomSeedPersistentParent =
              tmpfileSummary future.boot.initrd.systemd.tmpfiles.settings.preservation
                "/sysroot/persist/var/lib/systemd"
                "d";
            networkConnections =
              tmpfileSummary future.systemd.tmpfiles.settings.preservation
                "/persist/etc/NetworkManager/system-connections"
                "d";
            mullvadState =
              tmpfileSummary future.systemd.tmpfiles.settings.preservation "/persist/etc/mullvad-vpn"
                "d";
            atticQueue =
              tmpfileSummary future.systemd.tmpfiles.settings.preservation "/persist/var/lib/private/attic-upload"
                "d";
            userHome =
              tmpfileSummary future.systemd.tmpfiles.settings.preservation "/persist/home/${username}"
                "d";
          };
          expected = {
            machineIdPersistent = "f 0444 root:root ";
            machineIdVolatile = "f 0444 root:root ";
            randomSeedLink = "L 0600 root:root /persist/var/lib/systemd/random-seed";
            randomSeedPersistentParent = "d 0755 root:root ";
            networkConnections = "d 0700 root:root ";
            mullvadState = "d 0755 root:root ";
            atticQueue = "d 0750 root:root ";
            userHome = "d 0700 ${username}:users ";
          };
        };

        testDirectIdentitiesAreNotBindMounted = {
          expr = lib.all (path: lib.hasInfix path (builtins.toJSON state) == false) [
            "/var/lib/sops-nix"
            "/etc/ssh"
          ];
          expected = true;
        };
      };
    };
}
