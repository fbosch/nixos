_: {
  flake.meta = {
    user = {
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
    };

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
      defaultMode = "tuigreet"; # Options: "tuigreet" | "hyprlock-autologin"
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
