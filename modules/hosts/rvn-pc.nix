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
        { pkgs
        , lib
        , config
        , ...
        }:
        {
          # # CachyOS kernel experiment
          # nixpkgs.overlays = [ inputs.nix-cachyos-kernel.overlays.pinned ];
          # boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;
          #
          # # Binary cache for CachyOS kernels
          # nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian" ];
          # nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];

          environment.systemPackages = [
            pkgs.wlr-randr
          ];

          environment.sessionVariables = {
            LIBVA_DRIVER_NAME = "nvidia";
            NVD_BACKEND = "direct"; # Use direct backend for better performance
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
    ];

    extraHomeManager = [
      config.flake.modules.homeManager.dotfiles
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
      (
        { config, ... }:
        {
          # Override XDG Downloads directory to use mounted storage
          xdg.userDirs = {
            enable = true;
            download = "/mnt/storage/Downloads";
            # Ensure the directory is created
          };
        }
      )
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  # Store the module
  flake.modules.nixos."hosts/rvn-pc" = hostResult._module;

  # Store the host config metadata
  flake.hostConfigs.rvn-pc = hostResult._hostConfig;
}
