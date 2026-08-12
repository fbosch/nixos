{ config, ... }:
{
  flake.modules.darwin."hosts/rvn-mac/home" = {
    home-manager.users.${config.flake.meta.user.username} = {
      home.stateVersion = "25.05";
    };
  };
}
