{
  flake.modules.nixos.system = { pkgs, ... }: {
    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 7d --keep 15";
      flake = "/home/fbb/nixos";
    };
    
    environment.systemPackages = [ pkgs.nh ];
  };
}
