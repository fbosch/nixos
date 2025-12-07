{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = config.flake.lib.mkHost {
    hostImports = [
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      (_: {
        environment.sessionVariables = {
          GSK_RENDERER = "cairo";
          WLR_RENDERER_ALLOW_SOFTWARE = "1";
        };

        security.sudo.extraConfig = ''
          Defaults timestamp_timeout = 120
        '';
      })
    ];

    nixos = [
      "system"
      "secrets"
      "vpn"
      "hardware"
      "hardware/fingerprint"
      "nas"
    ];

    modules = [
      "users"
      "fonts"
      "security"
      "desktop"
      "applications"
      "development"
      "shell"
    ];

    extraHomeManager = [
      config.flake.modules.homeManager.dotfiles
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
    ];

    inherit (config.flake.meta.user) username;
  };
}
