{ config, ... }:
let
  flakeConfig = config;
in
{
  flake.modules.nixos.nas =
    { config, lib, ... }:
    let
      nixosConfig = config;
      # NAS server configuration
      nasHostname = flakeConfig.flake.meta.nas.hostname;
      nasIpAddress = flakeConfig.flake.meta.nas.ipAddress;
      encryptedConditionPath = "/run/nas/encrypted.available";

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
      cifsOptions = "credentials=${nixosConfig.sops.templates.smbcredentials.path},uid=${flakeConfig.flake.meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";

      # Generate tmpfile rule for a share
      mkTmpfileRule = share: "d /mnt/nas/${share} 0755 ${flakeConfig.flake.meta.user.username} users -";

      # Generate mount configuration for a share
      mkMount = share: {
        type = "cifs";
        what = "//${nasHostname}/${share}";
        where = "/mnt/nas/${share}";
        options = if share == "encrypted" then "${cifsOptions},nofail" else cifsOptions;
        unitConfig = {
          After = "network-online.target";
          Requires = "network-online.target";
        }
        // lib.optionalAttrs (share == "encrypted") {
          ConditionPathExists = encryptedConditionPath;
        };
      };

      # Generate automount configuration for a share
      mkAutomount = share: {
        where = "/mnt/nas/${share}";
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          After = "network-online.target";
        }
        // lib.optionalAttrs (share == "encrypted") {
          ConditionPathExists = encryptedConditionPath;
        };
        automountConfig = {
          TimeoutIdleSec = if share == "web" then "0" else "30s";
        };
      };
    in
    {
      # Add NAS hostname to /etc/hosts for reliable name resolution
      networking.hosts = {
        "${nasIpAddress}" = [ nasHostname ];
      };

      systemd = {
        tmpfiles.rules = [
          "d /mnt/nas 0755 ${flakeConfig.flake.meta.user.username} users -"
        ]
        ++ (map mkTmpfileRule shares);

        mounts = map mkMount shares;
        automounts = map mkAutomount shares;
      };
    };
}
