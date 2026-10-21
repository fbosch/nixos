{ config, ... }:
let
  flakeConfig = config;
  inherit (flakeConfig.flake.lib) sopsFiles sopsHelpers;
in
{
  flake.modules.nixos.nas =
    { config, lib, ... }:
    let
      nixosConfig = config;
      nasHostname = flakeConfig.flake.meta.nas.hostname;
      nasIpAddress = flakeConfig.flake.meta.nas.ipAddress;
      shares = nixosConfig.services.nas.smbShares;

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
        "credentials=${nixosConfig.sops.templates.smbcredentials.path},uid=${flakeConfig.flake.meta.user.username},gid=${shareGroup share},forceuid,forcegid,iocharset=utf8,file_mode=0660,dir_mode=0770,vers=3.1.1";

      mkTmpfileRule =
        share: "d /mnt/nas/${share} 0770 ${flakeConfig.flake.meta.user.username} ${shareGroup share} -";

      mkMount = share: {
        type = "cifs";
        what = "//${nasHostname}/${share}";
        where = "/mnt/nas/${share}";
        options = if share == "encrypted" then "${cifsOptionsFor share},nofail" else cifsOptionsFor share;
        unitConfig = {
          After = "network-online.target";
          Requires = "network-online.target";
        };
      };

      mkAutomount = share: {
        where = "/mnt/nas/${share}";
        wantedBy = [ "multi-user.target" ];
        automountConfig = {
          TimeoutIdleSec = if lib.elem share persistentShares then "0" else "30s";
        };
      };
    in
    {
      options.services.nas.smbShares = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "homes"
          "music"
          "photo"
          "video"
          "web"
          "downloads"
          "backup"
          "cloud-backup"
          "FrederikDocs"
          "websites"
          "encrypted"
          "LaCie"
        ];
        description = "NAS shares mounted through SMB; NFS aspects own their shares separately.";
      };

      config = {
        sops = {
          secrets = sopsHelpers.mkSecretsWithOpts sopsFiles.common sopsHelpers.rootOnly [
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
    };
}
