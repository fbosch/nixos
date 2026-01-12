{ inputs
, config
, ...
}:

{
  flake.modules.darwin."hosts/rvn-mac" =
    { pkgs, meta, ... }:
    {
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
          };

          finder = {
            AppleShowAllExtensions = true;
            FXPreferredViewStyle = "Nlsv"; # List view
            ShowPathbar = true;
          };

          NSGlobalDomain = {
            AppleShowAllExtensions = true;
            InitialKeyRepeat = 15;
            KeyRepeat = 2;
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

      # Homebrew configuration
      homebrew = {
        enable = true;
        onActivation = {
          autoUpdate = true;
          cleanup = "zap"; # Uninstall packages not in config
          upgrade = true;
        };

        # GUI Applications (casks)
        casks = [
          "wezterm"
          "raycast"
          "numi"
          "font-noto-sans-runic"
          "rectangle"
          "bitwarden"
          "1password"
          "firefox"
          "floorp"
          "arc"
          "zen"
          "alt-tab"
          "replacicon"
          "cursor"
        ];

        # CLI tools that work better via Homebrew on macOS
        # (Most CLI tools should be in nixpkgs, but some may need Homebrew)
        brews = [
          # Add any brews here that don't work well in Nix
        ];
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
