{ config, inputs, ... }:
let
  targetDevice = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746";
  devices = {
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
in
{
  imports = [ inputs.disko.flakeModules.disko ];

  flake = {
    diskoConfigurations.rvn-pc = {
      disko.devices = devices;
    };

    modules.nixos."hosts/rvn-pc/disko" = {
      imports = [ inputs.disko.nixosModules.disko ];
      disko.devices = devices;
    };
  };

  perSystem =
    { lib
    , system
    , ...
    }:
    let
      evaluatedConfig = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          config.flake.modules.nixos."hosts/rvn-pc/disko"
          { system.stateVersion = "25.05"; }
        ];
      };
      evaluated = evaluatedConfig.config;
    in
    {
      nix-unit.tests.rvnPcDisko =
        lib.recursiveUpdate
          {
            testTargetDevice = {
              expr = devices.disk.system.device;
              expected = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746";
            };

            testOnlyApprovedDisk = {
              expr = builtins.attrNames devices.disk;
              expected = [ "system" ];
            };

            testPartitionContract = {
              expr =
                let
                  partitions = devices.disk.system.content.partitions;
                in
                {
                  ESP = {
                    inherit (partitions.ESP) device size;
                    partitionType = partitions.ESP.type;
                    contentType = partitions.ESP.content.type;
                    inherit (partitions.ESP.content)
                      format
                      mountOptions
                      mountpoint
                      ;
                  };
                  swap = {
                    inherit (partitions.swap) device size;
                    inherit (partitions.swap.content) priority resumeDevice type;
                  };
                  system = {
                    inherit (partitions.system) device size;
                    inherit (partitions.system.content) extraArgs type;
                  };
                };
              expected = {
                ESP = {
                  device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part1";
                  size = "2G";
                  partitionType = "EF00";
                  contentType = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
                swap = {
                  device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part2";
                  size = "48G";
                  type = "swap";
                  priority = 0;
                  resumeDevice = true;
                };
                system = {
                  device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3";
                  size = "100%";
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                };
              };
            };

            testBtrfsSubvolumes = {
              expr = devices.disk.system.content.partitions.system.content.subvolumes;
              expected = {
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

            testTmpfsRoot = {
              expr = devices.nodev."/";
              expected = {
                fsType = "tmpfs";
                mountOptions = [
                  "mode=755"
                  "size=25%"
                ];
              };
            };

            testProtectedDisksAbsent = {
              expr = lib.all (value: lib.hasInfix value (builtins.toJSON devices) == false) [
                "AC7674097673D316"
                "B86CB0876CB04244"
                "ata-KINGSTON_SA400S37960G_50026B7783A2013B"
                "ata-ST2000DM001-1ER164_Z4Z13XS1"
                "/dev/sda"
                "/dev/sdb"
                "/dev/nvme0n1"
                "/dev/disk/by-partlabel"
                "/mnt/storage"
                "/mnt/games"
                "luks"
                "ntfs"
              ];
              expected = true;
            };
          }
          (
            lib.optionalAttrs (system == "x86_64-linux") {
              testEvaluatedFilesystems = {
                expr =
                  builtins.mapAttrs
                    (_path: value: {
                      inherit (value) device fsType options;
                    })
                    (
                      lib.getAttrs [
                        "/"
                        "/boot"
                        "/nix"
                        "/persist"
                      ]
                        evaluated.fileSystems
                    );
                expected = {
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
                    device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part1";
                    fsType = "vfat";
                    options = [ "umask=0077" ];
                  };
                  "/nix" = {
                    device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3";
                    fsType = "btrfs";
                    options = [
                      "x-initrd.mount"
                      "compress=zstd"
                      "noatime"
                      "subvol=/nix"
                    ];
                  };
                  "/persist" = {
                    device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part3";
                    fsType = "btrfs";
                    options = [
                      "compress=zstd"
                      "noatime"
                      "subvol=/persist"
                    ];
                  };
                };
              };

              testEvaluatedSwap = {
                expr = {
                  resumeDevice = evaluated.boot.resumeDevice;
                  swapDevices = map
                    (value: {
                      inherit (value) device priority;
                    })
                    evaluated.swapDevices;
                };
                expected = {
                  resumeDevice = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part2";
                  swapDevices = [
                    {
                      device = "/dev/disk/by-id/nvme-WDS200T3X0C-00SJG0_21031B801746-part2";
                      priority = 0;
                    }
                  ];
                };
              };
            }
          );
    };
}
