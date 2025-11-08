{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = config.flake.lib.mkHost {
    hostImports = [
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      ({ meta, ... }: {
        environment.sessionVariables = {
          GSK_RENDERER = "cairo";
          WLR_RENDERER_ALLOW_SOFTWARE = "1";
        };

        services.getty.autologinUser = meta.user.username;
        security.sudo.extraConfig = ''
          Defaults timestamp_timeout = 120
        '';
      })
    ];

    nixos = [
      "system"
      "users"
      "vpn"
      "fonts"
      "flatpak"
      "security"
      "desktop"
      "development"
      "applications"
      "shell"
      "hardware/fingerprint"
      "nas"
    ];

    homeManager = [
      "users"
      "dotfiles"
      "fonts"
      "flatpak"
      "security"
      "desktop"
      "applications"
      "development"
      "shell"
      "services"
    ];

    extraHomeManager = [
      inputs.flatpaks.homeManagerModules.nix-flatpak
      inputs.vicinae.homeManagerModules.default
    ];

    inherit (config.flake.meta.user) username;
  };
}
