{ lib }:
let
  hostSystem = import ./host-system.nix { inherit lib; };

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

  nixDistributionType = lib.types.enum [
    "upstream"
    "determinate"
  ];
in
lib.types.submodule (
  { config, ... }: {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Flake host identifier";
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
      sshAgent = lib.mkOption {
        type = lib.types.enum [
          "gpg"
          "ssh-agent"
        ];
        default = "ssh-agent";
        description = "Owner of the user's SSH agent socket";
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
      primaryUser = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Existing account used for per-user system configuration";
      };
      nixDistribution = lib.mkOption {
        type = nixDistributionType;
        default = "upstream";
        description = "Nix distribution installed on this host";
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
        apply =
          system:
          if system == null then
            throw "Host `${config.name}` must define system"
          else
            hostSystem {
              inherit system;
              hostName = config.name;
            };
        description = "Canonical Nix system double for this host";
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
)
