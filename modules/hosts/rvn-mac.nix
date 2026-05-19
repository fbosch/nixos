{ config, ... }:
let
  hostMeta = {
    name = "rvn-mac";
    role = "laptop";
    sshAlias = "mac";
    tailscale = "100.118.36.81";
    local = "192.168.167.54";
    sshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKFeunJFBraRV+0gG6sjGxCu0iEPMvxvDlfAb7FxribY";
    useTailnet = true;
    system = "aarch64-darwin";
    platform = {
      os = "darwin";
      arch = "arm64";
    };
    hardware = {
      vendor = "Apple";
      model = "MacBook Pro (2024)";
      memoryGiB = 24;
      cpu = {
        vendor = "Apple";
        model = "M4 Pro";
        family = "Apple Silicon";
        cores = 14;
      };
      gpu = {
        vendor = "Apple";
        model = "M4 Pro";
        kind = "integrated";
      };
    };
  };
in
{
  flake = {
    meta.hosts = [ hostMeta ];

    modules.darwin."hosts/rvn-mac" =
      { pkgs, ... }:
      {
        imports = config.flake.lib.resolveDarwin [
          # Darwin core system configuration (Cachix, nix settings, home-manager)
          "system"

          # Darwin-specific modules
          "fonts"
          "security"
          "secrets"
          "homebrew"
          "files/wakatime"
          "files/npmrc"
        ];

        # Home Manager configuration for user
        home-manager.users.${config.flake.meta.user.username} = {
          home.stateVersion = "25.05";

          # Home Manager modules (cross-platform)
          imports = config.flake.lib.resolveHm [
            # Home Manager preset modules
            "users"
            "dotfiles"
            "fonts"
            "security"
            "development"
            "worktrunk"
            "shell"
            "virtualization/podman"

            # Secrets for home-manager context
            "secrets"
          ];
        };

        # Set hostname so SSH config can identify this host and use Tailnet addresses
        networking.hostName = hostMeta.name;

        # macOS system configuration
        system = {
          stateVersion = 5;
          primaryUser = config.flake.meta.user.username;
          keyboard = {
            enableKeyMapping = true;
            remapCapsLockToControl = true;
          };
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
              NSWindowShouldDragOnGesture = true;
              "com.apple.swipescrolldirection" = false;
            };

            CustomUserPreferences = {
              "com.knollsoft.Rectangle" = {
                allowAnyShortcut = 1;
                alternateDefaultShortcuts = 1;
                launchOnLogin = 1;
                windowSnapping = 1;
              };

              "com.lwouis.alt-tab-macos" = {
                cursorFollowFocus = 1;
                cursorFollowFocusEnabled = true;
                hideAppBadges = false;
                hideColoredCircles = true;
                hideSpaceNumberLabels = true;
                hideStatusIcons = true;
                hideWindowlessApps = true;
                previewFocusedWindow = true;
                showTabsAsWindows = false;
                vimKeysEnabled = false;
              };
            };
          };
        };

        nix.settings = {
          # Add user to trusted users (core already adds @admin)
          trusted-users = [ config.flake.meta.user.username ];

          # Keep rebuilds responsive on this laptop.
          max-jobs = 4;
          cores = 2;
        };

        # direnv 2.37.x runs long shell tests on darwin during checkPhase.
        # Keep rvn-mac rebuilds fast by skipping upstream checks for this host.
        nixpkgs.overlays = [
          (_: prev: {
            direnv = prev.direnv.overrideAttrs (_: {
              doCheck = false;
            });
          })
        ];

        # Enable biometric auth for sudo on macOS
        security.pam.services.sudo_local.touchIdAuth = true;

        # System environment
        environment = {
          systemPackages = with pkgs; [
            nh
            nix-output-monitor
            keychain
            neovim
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
