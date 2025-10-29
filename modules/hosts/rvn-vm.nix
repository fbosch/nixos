{ inputs, config, ... }:

{
  flake.modules.nixos."hosts/rvn-vm" = {
    imports = with config.flake.modules.nixos; [
      config.flake.modules.nixos."system/core"
      config.flake.modules.nixos."system/locale"
      config.flake.modules.nixos."users/fbb/system"
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
            config.flake.modules.homeManager."users/fbb/home"
            dotfiles
            programs
            flatpak
            fonts
            gtk
            
            # Desktop
            config.flake.modules.homeManager."desktop/terminals"
            config.flake.modules.homeManager."desktop/wayland"
            config.flake.modules.homeManager."desktop/gnome"
            config.flake.modules.homeManager."desktop/theming"
            
            # Applications
            config.flake.modules.homeManager."applications/browsers"
            config.flake.modules.homeManager."applications/productivity"
            config.flake.modules.homeManager."applications/security"
            config.flake.modules.homeManager."applications/gaming"
            
            # Development
            config.flake.modules.homeManager."development/editors"
            config.flake.modules.homeManager."development/languages"
            config.flake.modules.homeManager."development/git"
            config.flake.modules.homeManager."development/tools"
            
            # Shell
            config.flake.modules.homeManager."shell/fish"
            config.flake.modules.homeManager."shell/utilities"
            config.flake.modules.homeManager."shell/monitoring"
            
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
