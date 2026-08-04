{ config, ... }:
{
  flake.modules.darwin."hosts/kmd-mac/home" =
    { lib, hostMeta, ... }:
    let
      username = hostMeta.primaryUser;
    in
    {
      home-manager.users.${username} = {
        home = {
          inherit username;
          homeDirectory = lib.mkForce "/Users/${username}";
          stateVersion = "25.05";
        };

        imports = config.flake.lib.resolveHm [
          "dotfiles"
          "fonts"
          "security"
          "development"
          "worktrunk"
          "shell"
          "virtualization/podman"
        ];
      };
    };
}
