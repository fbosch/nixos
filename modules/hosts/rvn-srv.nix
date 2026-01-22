{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "server";

    hostImports = [
      ../../machines/msi-cubi/configuration.nix
      ../../machines/msi-cubi/hardware-configuration.nix
     inputs.grub2-themes.nixosModules.default
      (
        { pkgs
        , ...
        }:
        {
          # environment.systemPackages = [
          #   pkgs.wlr-randr
          # ];
          #
          # environment.sessionVariables = {
          #   LIBVA_DRIVER_NAME = "nvidia";
          #   NVD_BACKEND = "direct";
          #   TERMINAL = "wezterm";
          #   GBM_BACKEND = "nvidia_drm";
          #   __GLX_VENDOR_LIBRARY_NAME = "nvidia";
          #   ELECTRON_OZONE_PLATFORM_HINT = "auto";
          #   GTK_USE_PORTAL = "0";
          # };
        }
      )
    ];

    modules = [
      # "nas"
    ];


    extraHomeManager = [
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
      (
        _:
        {
          # xdg.userDirs = {
          #   enable = true;
          #   download = "/mnt/storage/Downloads";
          # };
        }
      )
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  flake.modules.nixos."hosts/rvn-srv" = hostResult._module;

  flake.hostConfigs.rvn-pc = hostResult._hostConfig;
}
