{
  flake.modules.nixos.system = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ cifs-utils nfs-utils samba ];
  };
}
