{ inputs, config, ... }:
{
  flake.modules.nixos."hosts/rvn-pc/home" = {
    home-manager.users.${config.flake.meta.user.username}.imports =
      config.flake.lib.resolveHm [
        # Desktop preset (includes users, dotfiles, fonts, security, desktop, applications, development, shell)
        "presets/desktop"
        "applications/surge"
        "windows"
        "worktrunk"
        "virtualization/podman"

        # Shared modules with Home Manager components
        "secrets"
      ]
      ++ [
        # External Home Manager modules
        inputs.flatpaks.homeManagerModules.nix-flatpak

        # User directory configuration
        {
          xdg.userDirs = {
            enable = true;
            setSessionVariables = true;
            download = "/mnt/storage/Downloads";
          };

          services.surge = {
            autostart = true;
            settings = {
              general.default_download_dir = "/mnt/storage/Downloads";
              network.proxy_url = "http://192.168.1.46:8889";
            };
          };

          headroom.service.enable = true;
        }
      ];
  };
}
