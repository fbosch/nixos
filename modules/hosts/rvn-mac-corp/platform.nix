{ config, ... }:
{
  flake.modules.darwin."hosts/rvn-mac-corp/platform" =
    { pkgs, lib, ... }:
    {
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
            NSGlobalDomain.NSUserKeyEquivalents = {
              Hide = "@^~$h";
              "Hide Others" = "@^~$o";
            };

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
      # Keep rvn-mac-corp rebuilds fast by skipping upstream checks for this host.
      nixpkgs.overlays = [
        (_: prev: {
          direnv = prev.direnv.overrideAttrs (_: {
            doCheck = false;
          });

          _1password-gui = prev._1password-gui.overrideAttrs (
            old:
            lib.optionalAttrs (old.version or null == "8.12.21") {
              src = prev.fetchurl {
                url = "https://downloads.1password.com/mac/1Password-8.12.21-aarch64.zip";
                hash = "sha256-WrWbGzBK65tVNl9Dc3OnJURiPpfbNLOYUJcVT0ETaAs=";
              };
            }
          );
        })
      ];

      # Enable biometric auth for sudo on macOS
      security.pam.services.sudo_local.touchIdAuth = true;

      environment = {
        systemPackages = with pkgs; [
          nh
          nix-output-monitor
          keychain
          neovim
          wezterm
          rectangle
          _1password-gui
        ];
        variables.NH_FLAKE = "/Users/${config.flake.meta.user.username}/nixos";
        shells = [ pkgs.fish ];
      };

      users.users.${config.flake.meta.user.username} = {
        home = "/Users/${config.flake.meta.user.username}";
        shell = pkgs.fish;
        ignoreShellProgramCheck = true;
      };
    };
}
