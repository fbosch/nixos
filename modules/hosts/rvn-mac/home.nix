{ config, ... }:
{
  flake.modules.darwin."hosts/rvn-mac/home" = {
    home-manager.users.${config.flake.meta.user.username} = {
      home.stateVersion = "25.05";

      imports = config.flake.lib.resolveHm [
        # Home Manager preset modules
        "users"
        "dotfiles"
        "fonts"
        "security"
        "development"
        "worktrunk"
        "shell"
        "virtualization/podman"

        # Secrets for home-manager context
        "secrets"
      ];
    };
  };
}
