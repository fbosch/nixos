{ config, ... }:
let
  inherit (config.flake.lib) sopsFiles;
  inherit (config.flake.meta.user) username;
in
{
  flake.modules.nixos."hosts/rvn-pc/login" = { config, ... }: {
    sops.secrets.user-password-hash = {
      sopsFile = sopsFiles.hosts."rvn-pc";
      neededForUsers = true;
      mode = "0400";
    };

    users = {
      mutableUsers = false;
      users.${username} = {
        uid = 1000;
        hashedPasswordFile = config.sops.secrets.user-password-hash.path;
      };
    };
  };
}
