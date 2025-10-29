{
  flake.modules.homeManager.users.fbb.home = {
    programs.home-manager.enable = true;
    systemd.user.startServices = "sd-switch";

    home = {
      username = "fbb";
      homeDirectory = "/home/fbb";
      stateVersion = "25.05";
    };
  };
}
