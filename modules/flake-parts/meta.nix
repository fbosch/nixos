{ lib, ... }:
let
  user = rec {
    username = "fbb";
    fullName = "Frederik Bosch";
    email = "fbosch@corax.aleeas.com";
    github = {
      username = "fbosch";
    };
    gpg = {
      fingerprint = "5E0F EC74 518E D5FE AA5E  A33E 5C49 A562 D850 322A";
      publicKeyFile = ../../configs/gpg/public-key.asc;
    };
    ssh = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJl/WCQsXEkE7em5A6d2Du2JAWngIPfA8sVuJP/9cuyq fbb@nixos"
      ];
    };
    avatar = {
      # Path to custom avatar file, or null to auto-fetch from GitHub
      source = null;
      # SHA256 hash of the GitHub avatar
      # To update: nix-prefetch-url https://github.com/fbosch.png
      # Or run: ./scripts/update-avatar.sh
      sha256 = "13yl42iqd2a37k8cilssky8dw182cma5cq57jzaw1m7bnxdcf421";
      # URL is constructed from github.username
      url = "https://github.com/${github.username}.png";
    };
  };

  gpuKindType = lib.types.enum [
    "integrated"
    "discrete"
    "virtual"
  ];

  hostRoleType = lib.types.enum [
    "server"
    "desktop"
    "laptop"
    "vm"
  ];

  hostOsType = lib.types.enum [
    "linux"
    "darwin"
  ];

  hostArchType = lib.types.enum [
    "x86_64"
    "arm64"
  ];
in
{
  # Declare options for flake metadata
  options.flake.meta = {
    user = lib.mkOption {
      type = lib.types.unspecified;
      description = "User metadata";
    };

    dotfiles = lib.mkOption {
      type = lib.types.unspecified;
      default = { };
      description = "Dotfiles configuration";
    };

    nas = lib.mkOption {
      type = lib.types.unspecified;
      default = { };
      description = "NAS configuration";
    };

    synology = lib.mkOption {
      type = lib.types.unspecified;
      default = { };
      description = "Synology configuration";
    };

    unfree = lib.mkOption {
      type = lib.types.submodule {
        options.allowList = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Package names allowed to be unfree";
        };
      };
      default = { };
      description = "Unfree package policy";
    };

    hosts = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Full host name (matches flake host id)";
            };
            role = lib.mkOption {
              type = hostRoleType;
              description = "Primary role of this host";
            };
            sshAlias = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional short SSH alias";
            };
            tailscale = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Tailscale IP address";
            };
            local = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Local network IP address";
            };
            sshPublicKey = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "SSH public key for this host";
            };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Optional: Override default username for SSH connections";
            };
            useTailnet = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Prefer Tailnet IPs when initiating SSH from this host";
            };
            corporate = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether this host avoids personal network, secret, and remote-access integrations.";
            };
            system = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Nix system triple for this host";
            };
            platform = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    os = lib.mkOption {
                      type = hostOsType;
                      description = "Operating system family";
                    };
                    arch = lib.mkOption {
                      type = hostArchType;
                      description = "CPU architecture";
                    };
                  };
                }
              );
              default = null;
              description = "Normalized platform metadata";
            };
            hardware = lib.mkOption {
              type = lib.types.nullOr (
                lib.types.submodule {
                  options = {
                    vendor = lib.mkOption {
                      type = lib.types.str;
                      description = "Hardware vendor";
                    };
                    model = lib.mkOption {
                      type = lib.types.str;
                      description = "Hardware model";
                    };
                    memoryGiB = lib.mkOption {
                      type = lib.types.nullOr lib.types.int;
                      default = null;
                      description = "Installed system memory in GiB";
                    };
                    cpu = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            vendor = lib.mkOption {
                              type = lib.types.str;
                              description = "CPU vendor";
                            };
                            model = lib.mkOption {
                              type = lib.types.str;
                              description = "CPU model";
                            };
                            family = lib.mkOption {
                              type = lib.types.nullOr lib.types.str;
                              default = null;
                              description = "CPU family or microarchitecture";
                            };
                            cores = lib.mkOption {
                              type = lib.types.nullOr lib.types.int;
                              default = null;
                              description = "Physical CPU core count";
                            };
                          };
                        }
                      );
                      default = null;
                      description = "CPU metadata";
                    };
                    gpu = lib.mkOption {
                      type = lib.types.nullOr (
                        lib.types.submodule {
                          options = {
                            vendor = lib.mkOption {
                              type = lib.types.str;
                              description = "GPU vendor";
                            };
                            model = lib.mkOption {
                              type = lib.types.str;
                              description = "GPU model";
                            };
                            kind = lib.mkOption {
                              type = gpuKindType;
                              description = "GPU class";
                            };
                          };
                        }
                      );
                      default = null;
                      description = "GPU metadata";
                    };
                  };
                }
              );
              default = null;
              description = "Host hardware metadata";
            };
            dnsServers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "DNS servers for this host";
            };
          };
        }
      );
      default = [ ];
      description = "Network and SSH metadata for each host";
    };
  };

  config.flake.meta = {
    inherit user;

    dotfiles = {
      url = "https://github.com/fbosch/dotfiles";
    };

    nas = {
      hostname = "rvn-nas";
      ipAddress = "192.168.1.2";
    };

    synology = {
      domain = "corvus-corax.synology.me";
    };
  };
}
