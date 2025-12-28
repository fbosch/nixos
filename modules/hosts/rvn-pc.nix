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

          # Allow user access to Realforce keyboard for WebHID configuration
          services.udev.extraRules = ''
            # Topre Realforce keyboards - grant user access for configuration tools
            SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0853", ATTRS{idProduct}=="0317", MODE="0660", TAG+="uaccess"
          '';

          # Enable VAAPI hardware video acceleration with NVIDIA
          environment.sessionVariables = {
            LIBVA_DRIVER_NAME = "nvidia";
            NVD_BACKEND = "direct"; # Use direct backend for better performance
            TERMINAL = "wezterm";
          };

          # environment.sessionVariables = {
          #   GSK_RENDERER = "cairo";
          #   WLR_RENDERER_ALLOW_SOFTWARE = "1";
          #   TERMINAL = "foot";
          # };

          # security.sudo.extraConfig = ''
          #   Defaults timestamp_timeout = 120
          # '';

          # environment.systemPackages = [
          #   pkgs.local.chromium-realforce
          # ];
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
      # "hardware/fingerprint"
    ];

    extraHomeManager = [
      config.flake.modules.homeManager.dotfiles
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
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
