{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = {
    imports = [
      # Base system modules from dendritic tree
      config.flake.modules.nixos.base
      config.flake.modules.nixos.i18n
      config.flake.modules.nixos.vpn
      config.flake.modules.nixos.packages
      config.flake.modules.nixos.security
      config.flake.modules.nixos.hyprland
      config.flake.modules.nixos.audio
      
      # Machine-specific configuration (auto-generated on install)
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      
      # Home Manager integration
      {
        home-manager.users.fbb = {
          imports = [
            config.flake.modules.homeManager.base
            config.flake.modules.homeManager.dotfiles
            config.flake.modules.homeManager.programs
            config.flake.modules.homeManager.flatpak
            config.flake.modules.homeManager.fonts
            config.flake.modules.homeManager.gtk
            inputs.flatpaks.homeManagerModules.nix-flatpak
            inputs.vicinae.homeManagerModules.default
          ];
        };
        
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "hm-backup";
      }
    ];
  };
}
