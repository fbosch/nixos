{ config, ... }:
let
  flakeConfig = config;
  inherit (flakeConfig.flake.lib) sopsHelpers;
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

      mediaShares = [
        "music"
        "video"
        "downloads"
        "LaCie"
      ];

      persistentShares = [
        "web"
        "video"
        "LaCie"
      ];

      shareGroup = share: if lib.elem share mediaShares then "media" else "users";

      # Keep media services limited to shares they manage.
      cifsOptionsFor =
        share:
        "credentials=${nixosConfig.sops.templates.smbcredentials.path},uid=${flakeConfig.flake.meta.user.username},gid=${shareGroup share},forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";

      # Generate tmpfile rule for a share
      mkTmpfileRule =
        share: "d /mnt/nas/${share} 0755 ${flakeConfig.flake.meta.user.username} ${shareGroup share} -";

      # Generate mount configuration for a share
      mkMount = share: {
        type = "cifs";
        what = "//${nasHostname}/${share}";
        where = "/mnt/nas/${share}";
        options = if share == "encrypted" then "${cifsOptionsFor share},nofail" else cifsOptionsFor share;
        unitConfig = lib.mkMerge [
          {
            After = "network-online.target";
            Requires = "network-online.target";
          }
          (lib.optionalAttrs (share == "encrypted") {
            ConditionPathExists = encryptedConditionPath;
          })
        ];
      };

      # Generate automount configuration for a share
      mkAutomount = share: {
        where = "/mnt/nas/${share}";
        wantedBy = [ "multi-user.target" ];
        unitConfig = lib.optionalAttrs (share == "encrypted") {
          ConditionPathExists = encryptedConditionPath;
        };
        automountConfig = {
          TimeoutIdleSec = if lib.elem share persistentShares then "0" else "30s";
        };
      };
    in
    {
      sops = {
        secrets = sopsHelpers.mkSecretsWithOpts ../secrets/common.yaml sopsHelpers.rootOnly [
          "smb-username"
          "smb-password"
        ];

        templates."smbcredentials" = {
          content = ''
            username=${nixosConfig.sops.placeholder.smb-username}
            password=${nixosConfig.sops.placeholder.smb-password}
          '';
          mode = "0400";
          owner = "root";
          group = "root";
        };
      };

      users.groups.media = { };

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
