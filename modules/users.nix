{ config, ... }:
{
  flake.modules.nixos.users =
    { pkgs
    , lib
    , ...
    }:
    {
      users.users.${config.flake.meta.user.username} = {
        isNormalUser = lib.mkForce true;
        description = lib.mkForce config.flake.meta.user.fullName;
        openssh.authorizedKeys.keys = lib.mkForce config.flake.meta.user.ssh.authorizedKeys;
        extraGroups = lib.mkForce [
          "networkmanager"
          "wheel"
        ];
        shell = lib.mkForce pkgs.fish;
        ignoreShellProgramCheck = lib.mkForce true;
      };

    };

  flake.modules.homeManager.users =
    { pkgs
    , lib
    , ...
    }:
    let
      avatarFile =
        if config.flake.meta.user.avatar.source != null then
          config.flake.meta.user.avatar.source
        else
          pkgs.fetchurl {
            inherit (config.flake.meta.user.avatar) url sha256;
          };
    in
    {
      programs.home-manager.enable = true;
      systemd.user.startServices = lib.mkDefault "sd-switch";

      home = {
        inherit (config.flake.meta.user) username;
        homeDirectory = lib.mkDefault "/home/${config.flake.meta.user.username}";
        stateVersion = "25.05";

        # Link avatar to .face for display managers
        file.".face".source = avatarFile;
      };
    };
}
