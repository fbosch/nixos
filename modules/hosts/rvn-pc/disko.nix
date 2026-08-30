{ config, inputs, ... }:
let
  targetDevice = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746";
  explicitBtrfsMountHook = ''
    # util-linux 2.42 can use stale udev filesystem metadata after mkfs.
    # Disko knows these mounts are Btrfs, so bypass automatic type detection.
    mount() {
      command mount -t btrfs "$@"
    }
  '';
  plaintextDevices = {
    disk.system = {
      type = "disk";
      device = targetDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            device = "${targetDevice}-part1";
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = {
            device = "${targetDevice}-part2";
            size = "48G";
            content = {
              type = "swap";
              priority = 0;
              resumeDevice = true;
            };
          };

          system = {
            device = "${targetDevice}-part3";
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              preCreateHook = explicitBtrfsMountHook;
              preMountHook = explicitBtrfsMountHook;
              subvolumes = {
                "/nix" = {
                  mountpoint = "/nix";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
                "/persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                  ];
                };
              };
            };
          };
        };
      };
    };

    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "mode=755"
        "size=25%"
      ];
    };
  };
  encryptedDevices = {
    disk.system = {
      type = "disk";
      device = targetDevice;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            device = "${targetDevice}-part1";
            size = "2G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          encrypted = {
            device = "${targetDevice}-part2";
            size = "100%";
            content = {
              type = "luks";
              name = "cryptsystem";
              askPassword = true;
              extraFormatArgs = [
                "--type"
                "luks2"
              ];
              content = {
                type = "lvm_pv";
                vg = "rvnpc";
              };
            };
          };
        };
      };
    };

    lvm_vg.rvnpc = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "48G";
          content = {
            type = "swap";
            priority = 0;
            resumeDevice = true;
          };
        };

        system = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            preCreateHook = explicitBtrfsMountHook;
            preMountHook = explicitBtrfsMountHook;
            subvolumes = {
              "/nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "/persist" = {
                mountpoint = "/persist";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
            };
          };
        };
      };
    };

    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "mode=755"
        "size=25%"
      ];
    };
  };
in
{
  imports = [ inputs.disko.flakeModules.disko ];

  flake = {
    diskoConfigurations.rvn-pc = {
      disko.devices = encryptedDevices;
    };
    diskoConfigurations.rvn-pc-plaintext = {
      disko.devices = plaintextDevices;
    };

    modules.nixos."hosts/rvn-pc/disko" = {
      imports = [ inputs.disko.nixosModules.disko ];
      disko.devices = encryptedDevices;
    };
    modules.nixos."hosts/rvn-pc/plaintext-disko" = {
      imports = [ inputs.disko.nixosModules.disko ];
      disko.devices = plaintextDevices;
    };
  };

  perSystem =
    { lib
    , pkgs
    , system
    , ...
    }:
    let
      # Keep this literal independent from targetDevice so target drift breaks the safety check.
      approvedDisk = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746";
      approvedDevices = [
        approvedDisk
        "${approvedDisk}-part1"
        "${approvedDisk}-part2"
        "${approvedDisk}-part3"
      ];
      approvedEncryptedDevices = [
        approvedDisk
        "${approvedDisk}-part1"
        "${approvedDisk}-part2"
        "/dev/mapper/cryptsystem"
        "/dev/rvnpc/swap"
        "/dev/rvnpc/system"
      ];
      evaluatedConfig = config.flake.nixosConfigurations.rvn-pc;
      evaluated = evaluatedConfig.config;
      plaintextEvaluatedConfig = evaluatedConfig.extendModules {
        modules = [
          { disko.devices = lib.mkForce plaintextDevices; }
        ];
      };
      plaintextEvaluated = plaintextEvaluatedConfig.config;
      protectedReferences = [
        "/dev/disk/by-partlabel"
        "/dev/sda"
        "/dev/sdb"
        "/dev/nvme0n1"
        "AC7674097673D316"
        "B86CB0876CB04244"
        "ata-KINGSTON_SA400S37960G_50026B7783A2013B"
        "ata-ST2000DM001-1ER164_Z4Z13XS1"
        "/mnt/storage"
        "/mnt/games"
      ];
      filesystemOutcome = evaluatedConfiguration:
        builtins.mapAttrs
          (_path: value: {
            inherit (value) device fsType options;
          })
          (lib.getAttrs [ "/" "/boot" "/nix" "/persist" ] evaluatedConfiguration.fileSystems);
      expectedFileSystems = systemDevice: {
        "/" = {
          device = "tmpfs";
          fsType = "tmpfs";
          options = [
            "x-initrd.mount"
            "mode=755"
            "size=25%"
          ];
        };
        "/boot" = {
          device = "${approvedDisk}-part1";
          fsType = "vfat";
          options = [ "umask=0077" ];
        };
        "/nix" = {
          device = systemDevice;
          fsType = "btrfs";
          options = [
            "x-initrd.mount"
            "compress=zstd"
            "noatime"
            "subvol=/nix"
          ];
        };
        "/persist" = {
          device = systemDevice;
          fsType = "btrfs";
          options = [
            "x-initrd.mount"
            "compress=zstd"
            "noatime"
            "subvol=/persist"
          ];
        };
      };
      swapOutcome = evaluatedConfiguration: {
        resumeDevice = evaluatedConfiguration.boot.resumeDevice;
        swapDevices = map
          (value: {
            inherit (value) device priority;
          })
          evaluatedConfiguration.swapDevices;
      };
      expectedSwap = device: {
        resumeDevice = device;
        swapDevices = [
          {
            inherit device;
            priority = 0;
          }
        ];
      };
      checkDiskoScript =
        { name
        , script
        , allowedDevices
        , extraForbidden ? [ ]
        ,
        }:
        pkgs.runCommand name { } ''
          diskoScript=${script}
          referencedDevices="$(${pkgs.gnugrep}/bin/grep -oE '/dev/(disk/by-id/[A-Za-z0-9._:+-]*[A-Za-z0-9._+-]|mapper/[A-Za-z0-9._+-]+|rvnpc/[A-Za-z0-9._+-]+)' "$diskoScript" \
            | ${pkgs.coreutils}/bin/sort -u \
            || true)"

          for expected in ${lib.escapeShellArgs allowedDevices}; do
            if ! printf '%s\n' "$referencedDevices" | ${pkgs.gnugrep}/bin/grep -Fqx -- "$expected"; then
              echo "Missing approved Disko device: $expected" >&2
              exit 1
            fi
          done

          unexpectedDevices="$(
            printf '%s\n' "$referencedDevices" \
              | ${pkgs.gnugrep}/bin/grep -Fvx ${
                lib.concatMapStringsSep " " (value: "-e ${lib.escapeShellArg value}") allowedDevices
              } \
              || true
          )"
          if [ -n "$unexpectedDevices" ]; then
            echo "Unexpected Disko device references:" >&2
            printf '%s\n' "$unexpectedDevices" >&2
            exit 1
          fi

          if ${pkgs.gnugrep}/bin/grep -Eq '(^|[=" ])/dev/(sd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z]|mmcblk|md[0-9]|dm-|loop[0-9])' "$diskoScript"; then
            echo "Disko script contains a kernel device path" >&2
            exit 1
          fi

          if ${pkgs.gnugrep}/bin/grep -Eq '(^|[="])/dev/disk/by-(partlabel|partuuid|uuid|path)/' "$diskoScript"; then
            echo "Disko script contains a non-approved persistent device namespace" >&2
            exit 1
          fi

          for forbidden in ${lib.escapeShellArgs (protectedReferences ++ extraForbidden)}; do
            if ${pkgs.gnugrep}/bin/grep -Fq -- "$forbidden" "$diskoScript"; then
              echo "Forbidden Disko reference: $forbidden" >&2
              exit 1
            fi
          done

          ${pkgs.coreutils}/bin/touch "$out"
        '';
    in
    {
      apps = lib.optionalAttrs (system == "x86_64-linux") {
        disko = {
          type = "app";
          program = "${inputs.disko.packages.${system}.disko}/bin/disko";
          meta.description = "Partition and mount disks with the repository-pinned Disko version";
        };
      };

      checks = lib.optionalAttrs (system == "x86_64-linux") {
        rvn-pc-disko-script = checkDiskoScript {
          name = "rvn-pc-disko-script-check";
          script = evaluated.system.build.diskoScript;
          allowedDevices = approvedEncryptedDevices;
          extraForbidden = [ "-part3" ];
        };
        rvn-pc-plaintext-disko-script = checkDiskoScript {
          name = "rvn-pc-plaintext-disko-script-check";
          script = plaintextEvaluated.system.build.diskoScript;
          allowedDevices = approvedDevices;
        };
      };

      nix-unit.tests = lib.optionalAttrs (system == "x86_64-linux") {
        rvnPcDisko = {
          testPlaintextBaseline = {
            expr = {
              fileSystems = filesystemOutcome plaintextEvaluated;
              swap = swapOutcome plaintextEvaluated;
            };
            expected = {
              fileSystems = expectedFileSystems "${approvedDisk}-part3";
              swap = expectedSwap "${approvedDisk}-part2";
            };
          };
        };

        rvnPcEncryptedDisko = {
          testInteractiveLuksTopology = {
            expr =
              let
                luks = encryptedDevices.disk.system.content.partitions.encrypted.content;
              in
              {
                luks2 = lib.elem "luks2" luks.extraFormatArgs;
                interactive = luks.askPassword && !(luks ? keyFile) && !(luks ? passwordFile);
                mapper = luks.name;
                volumeGroup = luks.content.vg;
                logicalVolumes = builtins.attrNames encryptedDevices.lvm_vg.rvnpc.lvs;
              };
            expected = {
              luks2 = true;
              interactive = true;
              mapper = "cryptsystem";
              volumeGroup = "rvnpc";
              logicalVolumes = [
                "swap"
                "system"
              ];
            };
          };

          testEvaluatedStorageAndInitrd = {
            expr = {
              fileSystems = filesystemOutcome evaluated;
              swap = swapOutcome evaluated;
              luks = evaluated.boot.initrd.luks.devices.cryptsystem.device;
              lvm = evaluated.boot.initrd.services.lvm.enable;
              modulesPresent = lib.all
                (module: lib.elem module evaluated.boot.initrd.availableKernelModules)
                [
                  "dm_mod"
                  "dm_crypt"
                ];
            };
            expected = {
              fileSystems = expectedFileSystems "/dev/rvnpc/system";
              swap = expectedSwap "/dev/rvnpc/swap";
              luks = "${approvedDisk}-part2";
              lvm = true;
              modulesPresent = true;
            };
          };
        };
      };
    };
}
