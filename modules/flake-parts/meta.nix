{ lib, ... }:
let
  user = rec {
    username = "fbb";
    fullName = "Frederik Bosch";
    email = "fbb.privacy+gpg@protonmail.com";
    github = {
      username = "fbosch";
    };
    gpg = {
      keyId = "5C49A562D850322A";
      fingerprint = "5E0F EC74 518E D5FE AA5E  A33E 5C49 A562 D850 322A";
      publicKeyFile = ../../configs/gpg/public-key.asc;
    };
    ssh = {
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9bFB0RZWl7ofsEMEW4i8UJv448U/RT429+roe1gc9K"
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

    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            hostname = lib.mkOption {
              type = lib.types.str;
              description = "Human-readable hostname";
            };
            tailscale = lib.mkOption {
              type = lib.types.str;
              description = "Tailscale IP address";
            };
            local = lib.mkOption {
              type = lib.types.str;
              description = "Local network IP address";
            };
            sshPublicKey = lib.mkOption {
              type = lib.types.str;
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
              description = "Use Tailnet IP for SSH connections to this host";
            };
            dnsServers = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "DNS servers for this host";
            };
          };
        }
      );
      default = { };
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
