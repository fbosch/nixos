{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = {
    imports = with config.flake.modules.nixos; [
      base
      i18n
      vpn
      packages
      security
      fonts
      hyprland
      audio
      
      ../../machines/virtualbox-vm/configuration.nix
      ../../machines/virtualbox-vm/hardware-configuration.nix
      
      {
        home-manager.users.fbb = {
          imports = with config.flake.modules.homeManager; [
            base
            dotfiles
            programs
            flatpak
            fonts
            gtk
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
