{
  flake.modules.nixos.users =
    {
      pkgs,
      meta,
      lib,
      config,
      ...
    }:
    {
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

      # # Prevent home-manager service from running on boot - only run on rebuild/switch
      # # This significantly reduces boot time by not re-running activation scripts
      # # that only need to run when the configuration changes
      # systemd.services."home-manager-${meta.user.username}" = {
      #   wantedBy = lib.mkForce [ ]; # Remove from multi-user.target
      # };
    };

  flake.modules.homeManager.users =
    { meta, pkgs, ... }:
    let
      avatarFile =
        if meta.user.avatar.source != null then meta.user.avatar.source
        else pkgs.fetchurl {
          url = meta.user.avatar.url;
          sha256 = meta.user.avatar.sha256;
        };
    in
    {
      programs.home-manager.enable = true;
      systemd.user.startServices = "sd-switch";

      home = {
        inherit (meta.user) username;
        homeDirectory = "/home/${meta.user.username}";
        stateVersion = "25.05";

        # Link avatar to .face for display managers
        file.".face".source = avatarFile;
      };
    };
}
