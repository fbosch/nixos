{ config, ... }:
{
  flake.modules.darwin."hosts/rvn-mac" =
    { pkgs, ... }:
    {
      imports = [
        config.flake.modules.darwin.security
        config.flake.modules.darwin.homebrew
      ];

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

      nixpkgs.config.allowUnfree = true;

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

      environment = {
        systemPackages = with pkgs; [
          nh
          nix-output-monitor
          keychain
          wezterm
          rectangle
          firefox
          bitwarden-desktop
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

      home-manager.users.${config.flake.meta.user.username} = {
        home.stateVersion = config.flake.meta.versions.homeManager;

        imports =
          builtins.map
            (
              m: config.flake.modules.homeManager.${m} or { }
            )
            (config.flake.meta.presets.homeManagerOnly.homeManager ++ [ "secrets" ]);
      };
    };
}
