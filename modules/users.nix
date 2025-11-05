{
  flake.modules.nixos.users = { pkgs, meta, ... }: {
    users.users.${meta.user.username} = {
      isNormalUser = true;
      description = meta.user.fullName;
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.fish;
      ignoreShellProgramCheck = true;
    };
  };

  flake.modules.homeManager.users = { meta, ... }: {
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";

    home = {
      inherit (meta.user) username;
      homeDirectory = "/home/${meta.user.username}";
      stateVersion = "25.05";
    };
  };
}
