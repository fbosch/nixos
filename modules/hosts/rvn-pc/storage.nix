{ config, ... }:
{
  flake.modules.nixos."hosts/rvn-pc/storage" = _: {
    # Enable NTFS support
    boot.supportedFilesystems = [ "ntfs" ];

    fileSystems = {
      # Mount 2TB HDD (shared with Windows)
      "/mnt/storage" = {
        device = "/dev/disk/by-uuid/AC7674097673D316";
        fsType = "ntfs";
        noCheck = true;
        options = [
          "rw" # Read-write access
          "uid=1000" # Owner UID (your user)
          "gid=100" # Group GID (users group)
          "dmask=022" # Directory permissions (755)
          "fmask=022" # File permissions (755) - allows execution
          "noatime" # Don't update access times (better performance)
          "nofail" # Do not block boot if the disk is unavailable
          "x-systemd.automount" # Mount on first access instead of during boot
        ];
      };

      # Mount Linux-only Games SSD
      "/mnt/games" = {
        device = "/dev/disk/by-uuid/ea2a9163-46aa-4c77-b044-359619f50cb1";
        fsType = "ext4";
        options = [
          "rw" # Read-write access
          "noatime" # Don't update access times (better performance)
          "nofail" # Do not block boot if the disk is unavailable
          "x-systemd.automount" # Mount on first access instead of during boot
        ];
      };

    };

    # Ensure mount points exist
    systemd.tmpfiles.rules = [
      "d /mnt/storage 0755 ${config.flake.meta.user.username} users -"
      "d /mnt/games 0755 ${config.flake.meta.user.username} users -"
    ];
  };
}
