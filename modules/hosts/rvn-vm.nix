{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = {
    imports = with config.flake.modules.nixos; [
      system
      users
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
            users
            dotfiles
            programs
            flatpak
            fonts
            gtk
            desktop
            applications
            development
            shell
            
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
