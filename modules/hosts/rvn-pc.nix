{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "desktop";
    displayManagerMode = "tuigreet";

    hostImports = [
      ../../machines/desktop/configuration.nix
      ../../machines/desktop/hardware-configuration.nix
      inputs.grub2-themes.nixosModules.default
      (
        {
          pkgs,
          lib,
          config,
          ...
        }:
        {
          environment.systemPackages = [
            pkgs.wlr-randr
          ];

          environment.sessionVariables = {
            LIBVA_DRIVER_NAME = "nvidia";
            NVD_BACKEND = "direct";
            TERMINAL = "wezterm";
            GBM_BACKEND = "nvidia_drm";
            __GLX_VENDOR_LIBRARY_NAME = "nvidia";
            ELECTRON_OZONE_PLATFORM_HINT = "auto";
            GTK_USE_PORTAL = "0";
          };
        }
      )
    ];

    modules = [
      "secrets"
      "nas"
      "gaming"
      "windows"
      "virtualization"
    ];

    extraNixos = [
      "hardware/storage"
      "hardware/fingerprint"
      "hardware/fancontrol"
    ];

    extraHomeManager = [
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
      (
        { config, ... }:
        {
          xdg.userDirs = {
            enable = true;
            download = "/mnt/storage/Downloads";
          };
        }
      )
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  flake.modules.nixos."hosts/rvn-pc" = hostResult._module;

  flake.hostConfigs.rvn-pc = hostResult._hostConfig;
}
