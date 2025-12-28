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

    bitwarden = {
      serverUrl = "https://vault.corvus-corax.synology.me";
    };

    ui = {
      emojiFont = "Apple Color Emoji";
    };

    displayManager = {
      # Default display manager mode for hosts
      # Can be overridden per-host in hostConfig
      defaultMode = "regreet"; # Options: "regreet" | "tuigreet" | "hyprlock-autologin" (legacy)
    };

    versions = {
      homeManager = "25.05";
    };

    presets = {
      # Full desktop environment with all features
      desktop = {
        modules = [
          "users"
          "fonts"
          "security"
          "desktop"
          "applications"
          "development"
          "shell"
        ];
        nixos = [
          "system"
          "vpn"
        ];
        homeManager = [ "dotfiles" ];
      };

      # Headless server with development tools
      server = {
        modules = [
          "users"
          "security"
          "development"
          "shell"
        ];
        nixos = [
          "system"
          "vpn"
        ];
        homeManager = [ "dotfiles" ];
      };

      # Minimal installation with only essentials
      minimal = {
        modules = [
          "users"
          "security"
        ];
        nixos = [ "system" ];
        homeManager = [ "dotfiles" ];
      };

      # Home Manager only (for macOS or non-NixOS systems)
      homeManagerOnly = {
        modules = [ ];
        nixos = [ ];
        homeManager = [
          "users"
          "dotfiles"
          "security"
          "development"
          "shell"
        ];
      };
    };

    unfree = {
      allowList = [
        "git-credential-manager"
        "steam"
        "steam-unwrapped"
      ];
    };
  };
}
