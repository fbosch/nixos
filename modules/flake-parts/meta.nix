_:
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
      # Primary SSH public key (from SOPS)
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9bFB0RZWl7ofsEMEW4i8UJv448U/RT429+roe1gc9K";
      # Additional authorized keys for different machines
      authorizedKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9bFB0RZWl7ofsEMEW4i8UJv448U/RT429+roe1gc9K" # Primary key
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEFNYtL1qSIxrsA27qkFRem9nj3hlR5vVyyaYO0otUNl frederik@bosch.dev" # Mac key
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
  flake.meta = {
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
