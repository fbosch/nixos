{
  flake.modules.nixos.system = {
    programs.nix-ld.enable = true;

    nixpkgs.config.allowUnfree = true;
    
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };
}
