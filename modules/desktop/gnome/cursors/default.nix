{
  flake.modules.nixos.desktop = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.local.win11osx-cursors ];
  };
}
