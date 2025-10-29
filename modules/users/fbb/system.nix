{
  flake.modules.nixos.users.fbb.system = {
    users.users.fbb = {
      isNormalUser = true;
      description = "Frederik Bosch";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };
  };
}
