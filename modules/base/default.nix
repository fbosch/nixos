{
  flake.modules.nixos.base = { config, pkgs, ... }: {
    programs.nix-ld.enable = true;
    
    time.timeZone = "Europe/Copenhagen";
    
    users.users.fbb = {
      isNormalUser = true;
      description = "Frederik Bosch";
      extraGroups = [
        "networkmanager"
        "wheel"
      ];
    };

    nixpkgs.config.allowUnfree = true;
    
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };

  };
}
