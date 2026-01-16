{ inputs
, config
, ...
}:

{
  flake.modules.darwin."hosts/rvn-mac" =
    { pkgs, meta, ... }:
    {
      imports = [
        config.flake.modules.darwin.security
        config.flake.modules.darwin.homebrew
      ];

      system = {
        stateVersion = 5;
        primaryUser = meta.user.username;
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

          universalaccess = {
            reduceMotion = true;
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
          meta.user.username
        ];
      };

      environment = {
        systemPackages = with pkgs; [
          nh
          nix-output-monitor
          keychain
          raycast
          wezterm
          rectangle
          firefox
          bitwarden-desktop
          _1password-gui
        ];
        variables.NH_FLAKE = "/Users/${meta.user.username}/nixos";
        shells = [ pkgs.fish ];
      };

      users.users.${meta.user.username} = {
        home = "/Users/${meta.user.username}";
        shell = pkgs.fish;
        ignoreShellProgramCheck = true;
      };

      home-manager.users.${meta.user.username} = {
        home.stateVersion = meta.versions.homeManager;

        imports =
          builtins.map
            (
              m: config.flake.modules.homeManager.${m} or { }
            )
            meta.presets.homeManagerOnly.homeManager;
      };
    };
}
