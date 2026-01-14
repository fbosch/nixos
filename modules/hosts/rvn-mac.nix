{ inputs
, config
, ...
}:

{
  flake.modules.darwin."hosts/rvn-mac" =
    { pkgs, meta, ... }:
    {
      # Import Darwin-specific modules
      imports = [
        config.flake.modules.darwin.security
        config.flake.modules.darwin.homebrew
      ];

      # Basic system settings
      system = {
        stateVersion = 5;
        # Set primary user for system defaults
        primaryUser = meta.user.username;
        # macOS system defaults
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

      # Allow unfree packages
      nixpkgs.config.allowUnfree = true;

      # Nix settings
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
        # NH (Nix Helper) for Darwin
        systemPackages = with pkgs; [
          nh
          nix-output-monitor
          keychain # SSH key manager for macOS
        ];
        # Set NH_FLAKE environment variable for nh commands
        variables.NH_FLAKE = "/Users/${meta.user.username}/nixos";
        # Fish shell is installed but configuration is managed in ~/dotfiles
        # We don't enable programs.fish to avoid conflicts with dotfiles config
        shells = [ pkgs.fish ];
      };

      # User configuration
      users.users.${meta.user.username} = {
        home = "/Users/${meta.user.username}";
        shell = pkgs.fish;
        ignoreShellProgramCheck = true; # i know what i'm doing
      };

      # Home Manager configuration using homeManagerOnly preset
      # This includes: users, dotfiles, security, development, shell modules
      home-manager.users.${meta.user.username} = {
        home.stateVersion = meta.versions.homeManager;

        imports =
          # Use homeManagerOnly preset modules (users, dotfiles, security, development, shell)
          builtins.map
            (
              m: config.flake.modules.homeManager.${m} or { }
            )
            meta.presets.homeManagerOnly.homeManager;
      };
    };
}
