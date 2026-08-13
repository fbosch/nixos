_: {
  # NixOS system-level module. Use the Darwin class for a Darwin-only feature.
  # This aspect owns package availability and machine state.
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

        # Generally available packages
        # environment.systemPackages = with pkgs; [
        #   # Desktop packages
        # ];

        # The host collector wires the matching Home Manager aspect when this
        # named aspect appears in hosts.<name>.modules.
      };
    };

  # Home Manager user-level sibling. This aspect owns user
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
