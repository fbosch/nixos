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

    # extraNixos = [ "hardware/fingerprint" ];

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
