{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.bibata-cursors ];
  };
}
