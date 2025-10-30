{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = config.flake.lib.mkHost {
    hardware = [
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
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
      "shell"
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

    username = "fbb";
  };
}
