{ config, ... }:
{
  # NixOS system-level module. Use the Darwin class for a Darwin-only feature.
  # This aspect owns package availability and machine state.
  flake.modules.nixos."<category>/<NAME>" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      config = {
        # System-level configuration
        # Example: Desktop environment
        # services.xserver.enable = true;
        # services.xserver.desktopManager.<NAME>.enable = true;

        # Generally available packages
        # environment.systemPackages = with pkgs; [
        #   # Desktop packages
        # ];

        # Include Home Manager auxiliary module
        home-manager.sharedModules = [
          config.flake.modules.homeManager."<category>/<NAME>"
        ];
      };
    };

  # Home Manager user-level module (auxiliary). This aspect owns user
  # configuration, generated files, services, and session state.
  flake.modules.homeManager."<category>/<NAME>" =
    { config, lib, ... }:
    {
      config = {
        # User-level configuration
        # Example: Desktop environment settings
        # dconf.settings = {
        #   "org/<NAME>/settings" = {
        #     theme = "dark";
        #   };
        # };
      };
    };
}
