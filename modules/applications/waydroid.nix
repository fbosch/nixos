{ pkgs, ... }:
{
  # NixOS module: Waydroid Android container
  flake.modules.nixos.waydroid =
    { pkgs
    , meta
    , lib
    , ...
    }:
    {
      virtualisation.waydroid.enable = true;

      users.users.${meta.user.username}.extraGroups = [ "waydroid" ];

      environment.systemPackages = with pkgs; [
        waydroid
        # wl-clipboard for clipboard sharing between host and Waydroid
        wl-clipboard
      ];

      # Required kernel modules for Waydroid
      boot.kernelModules = [
        "binder_linux"
        "ashmem_linux"
      ];

      # Allow Waydroid networking
      networking.firewall.trustedInterfaces = [ "waydroid0" ];
    };

  # Home Manager module: Waydroid user configuration
  flake.modules.homeManager.waydroid =
    { pkgs
    , lib
    , osConfig
    , ...
    }:
    lib.optionalAttrs osConfig.virtualisation.waydroid.enable {
      home.packages = with pkgs; [
        # WayDroid helper tools
        wl-clipboard
      ];
    };
}
