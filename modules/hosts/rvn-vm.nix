{ inputs, config, ... }:

let
  hostResult = config.flake.lib.mkHost {
    preset = "desktop";

    hostImports = [
      inputs.grub2-themes.nixosModules.default
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      (_: {
        environment.sessionVariables = {
          GSK_RENDERER = "cairo";
          WLR_RENDERER_ALLOW_SOFTWARE = "1";
          TERMINAL = "foot";
        };

        security.sudo.extraConfig = ''
          Defaults timestamp_timeout = 120
        '';

        # environment.systemPackages = [
        #   pkgs.local.chromium-realforce
        # ];
      })
    ];

    extraNixos = [ "secrets" "nas" ];

    extraHomeManager = [
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
    ];

    inherit (config.flake.meta.user) username;
  };
in
{
  # Store the module
  flake.modules.nixos."hosts/rvn-vm" = hostResult._module;

  # Store the host config metadata
  flake.hostConfigs.rvn-vm = hostResult._hostConfig;
}
