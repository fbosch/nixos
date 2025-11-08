{
  flake.modules.nixos.nas = { meta, ... }: {
    systemd = {
      tmpfiles.rules = [
        "d /mnt/nas 0755 ${meta.user.username} users -"
        "d /mnt/nas/homes 0755 ${meta.user.username} users -"
        "d /mnt/nas/music 0755 ${meta.user.username} users -"
        "d /mnt/nas/photo 0755 ${meta.user.username} users -"
        "d /mnt/nas/video 0755 ${meta.user.username} users -"
        "d /mnt/nas/web 0755 ${meta.user.username} users -"
        "d /mnt/nas/downloads 0755 ${meta.user.username} users -"
        "d /mnt/nas/cloud-backup 0755 ${meta.user.username} users -"
        "d /mnt/nas/FrederikDocs 0755 ${meta.user.username} users -"
        "d /mnt/nas/websites 0755 ${meta.user.username} users -"
      ];

      mounts = [
        {
          type = "cifs";
          what = "//rvn-nas/homes";
          where = "/mnt/nas/homes";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/music";
          where = "/mnt/nas/music";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/photo";
          where = "/mnt/nas/photo";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/video";
          where = "/mnt/nas/video";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/web";
          where = "/mnt/nas/web";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/downloads";
          where = "/mnt/nas/downloads";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/cloud-backup";
          where = "/mnt/nas/cloud-backup";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/FrederikDocs";
          where = "/mnt/nas/FrederikDocs";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
        {
          type = "cifs";
          what = "//rvn-nas/websites";
          where = "/mnt/nas/websites";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
        }
      ];

      automounts = [
        {
          where = "/mnt/nas/homes";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/music";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/photo";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/video";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/web";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/downloads";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/cloud-backup";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/FrederikDocs";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
        {
          where = "/mnt/nas/websites";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
      ];
    };
  };
}
