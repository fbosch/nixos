{ config, ... }:
let
  hostMeta = {
    name = "rvn-mac";
    sshAlias = "mac";
    tailscale = "100.118.36.81";
    local = "192.168.167.54";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFeunJFBraRV+0gG6sjGxCu0iEPMvxvDlfAb7FxribY";
    useTailnet = true;
  };
in
{
  # rvn-mac: Dendritic host configuration for MacBook Pro
  # Hardware: Apple Silicon MacBook Pro
  # Role: Development workstation running nix-darwin with Home Manager

  flake = {
    # Host metadata
    meta.hosts = [ hostMeta ];

    modules.darwin."hosts/rvn-mac" =
      { pkgs, ... }:
      {
        imports = config.flake.lib.resolveDarwin [
          # Darwin-specific modules
          "security"
          "secrets"
          "homebrew"
          "files/wakatime"
        ];

        # Home Manager configuration for user
        home-manager.users.${config.flake.meta.user.username} = {
          home.stateVersion = "25.05";

          # Home Manager modules (cross-platform)
          imports = config.flake.lib.resolveHm [
            # Home Manager preset modules
            "users"
            "dotfiles"
            "security"
            "development"
            "shell"
            "virtualization/podman"

            # Secrets for home-manager context
            "secrets"
          ];
        };

        # macOS system configuration
        system = {
          stateVersion = 5;
          primaryUser = config.flake.meta.user.username;
          defaults = {
            dock = {
              autohide = true;
              orientation = "bottom";
              show-recents = false;
              tilesize = 48;
              launchanim = false;
            };

            finder = {
              AppleShowAllExtensions = true;
              FXPreferredViewStyle = "Nlsv";
              ShowPathbar = true;
            };

            menuExtraClock = {
              Show24Hour = true;
              ShowDate = 0;
              ShowDayOfWeek = true;
            };

            NSGlobalDomain = {
              AppleInterfaceStyle = "Dark";
              AppleShowAllExtensions = true;
              InitialKeyRepeat = 15;
              KeyRepeat = 2;
              NSAutomaticCapitalizationEnabled = false;
              NSAutomaticPeriodSubstitutionEnabled = false;
              "com.apple.swipescrolldirection" = false;
            };
          };
        };

        # Allow unfree packages
        nixpkgs.config.allowUnfree = true;

        # Nix daemon configuration
        nix.settings = {
          experimental-features = [
            "nix-command"
            "flakes"
          ];
          trusted-users = [
            "@admin"
            config.flake.meta.user.username
          ];
        };

        # System environment
        environment = {
          systemPackages = with pkgs; [
            nh
            nix-output-monitor
            keychain
            wezterm
            rectangle
            tailscale
            bitwarden-desktop
            _1password-gui
          ];
          variables.NH_FLAKE = "/Users/${config.flake.meta.user.username}/nixos";
          shells = [ pkgs.fish ];
        };

        # User configuration
        users.users.${config.flake.meta.user.username} = {
          home = "/Users/${config.flake.meta.user.username}";
          shell = pkgs.fish;
          ignoreShellProgramCheck = true;
        };
      };
  };
}
