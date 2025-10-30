{
  flake.modules.nixos.users = { pkgs, ... }: {
    users.users.fbb = {
      isNormalUser = true;
      description = "Frederik Bosch";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
      shell = pkgs.fish;
      ignoreShellProgramCheck = true;
    };
  };
}
