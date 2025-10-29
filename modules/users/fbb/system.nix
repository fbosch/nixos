{
  flake.modules.nixos.users = {
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
