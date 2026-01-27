{ config, ... }:
{
  # NixOS system-level module
  flake.modules.nixos."<category>/<NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # System-level configuration
        # Example: Desktop environment
        # services.xserver.enable = true;
        # services.xserver.desktopManager.<NAME>.enable = true;

        # System packages
        # environment.systemPackages = with pkgs; [
        #   # Desktop packages
        # ];

        # Include Home Manager auxiliary module
        home-manager.sharedModules = [
          config.flake.modules.homeManager."<category>/<NAME>"
        ];
      };
    };

  # Home Manager user-level module (auxiliary)
  flake.modules.homeManager."<category>/<NAME>" =
    { config
    , lib
    , pkgs
    , ...
    }:
    {
      config = {
        # User-level configuration
        # Example: Desktop environment settings
        # dconf.settings = {
        #   "org/<NAME>/settings" = {
        #     theme = "dark";
        #   };
        # };

        # User packages
        # home.packages = with pkgs; [
        #   # User applications
        # ];
      };
    };
}
