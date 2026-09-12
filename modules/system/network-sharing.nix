{
  flake.modules.nixos.system = { pkgs, ... }: {
    boot.supportedFilesystems = [ "nfs" ];

    environment.systemPackages = with pkgs; [ cifs-utils nfs-utils samba ];
  };
}
