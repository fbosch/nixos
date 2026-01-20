{
  flake.modules.nixos.nas = { config, meta, ... }:
    let
      # NAS server configuration
      nasHostname = "rvn-nas";
      nasIpAddress = "192.168.1.2";

      # List of NAS shares to mount
      shares = [
        "homes"
        "music"
        "photo"
        "video"
        "web"
        "downloads"
        "cloud-backup"
        "FrederikDocs"
        "websites"
        "encrypted"
        "LaCie"
      ];

      # Common CIFS mount options
      cifsOptions =
        "credentials=${config.sops.templates.smbcredentials.path},uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";

      # Generate tmpfile rule for a share
      mkTmpfileRule = share:
        "d /mnt/nas/${share} 0755 ${meta.user.username} users -";

      # Generate mount configuration for a share
      mkMount = share: {
        type = "cifs";
        what = "//${nasHostname}/${share}";
        where = "/mnt/nas/${share}";
        options = cifsOptions;
      };

      # Generate automount configuration for a share
      mkAutomount = share: {
        where = "/mnt/nas/${share}";
        wantedBy = [ "multi-user.target" ];
        automountConfig = { TimeoutIdleSec = "30s"; };
      };
    in
    {
      # Add NAS hostname to /etc/hosts for reliable name resolution
      networking.hosts = {
        "${nasIpAddress}" = [ nasHostname ];
      };

      systemd = {
        tmpfiles.rules = [ "d /mnt/nas 0755 ${meta.user.username} users -" ]
          ++ (map mkTmpfileRule shares);

        mounts = map mkMount shares;
        automounts = map mkAutomount shares;
      };
    };
}
