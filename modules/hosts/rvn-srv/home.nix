{ config, ... }:
{
  flake.modules.nixos."hosts/rvn-srv/home" = {
    home-manager.users.${config.flake.meta.user.username} = {
      imports = config.flake.lib.resolveHm [
        # Server preset modules for Home Manager
        "users"
        "dotfiles"
        "security"
        "development"
        "shell"
        "applications/surge"

        # Secrets for home-manager context
        "secrets"
      ];

      services.surge = {
        autostart = true;
        settings = {
          general.default_download_dir = "/mnt/nas/downloads";
          network.proxy_url = "http://127.0.0.1:8889";
        };
      };
    };
  };
}
