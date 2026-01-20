{ config, ... }:
{
  flake.modules.nixos."hardware/storage" =
    _:
    {
      # Enable NTFS support
      boot.supportedFilesystems = [ "ntfs" ];

      # Mount 2TB HDD (shared with Windows)
      fileSystems."/mnt/storage" = {
        device = "/dev/disk/by-uuid/AC7674097673D316";
        fsType = "ntfs-3g";
        options = [
          "rw" # Read-write access
          "uid=1000" # Owner UID (your user)
          "gid=100" # Group GID (users group)
          "dmask=022" # Directory permissions (755)
          "fmask=022" # File permissions (755) - allows execution
          "big_writes" # Better write performance
          "noatime" # Don't update access times (better performance)
        ];
      };

      # Ensure mount point exists
      systemd.tmpfiles.rules = [
        "d /mnt/storage 0755 ${config.flake.meta.user.username} users -"
      ];
    };
}
