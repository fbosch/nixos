{
  flake.modules.nixos.nas = { meta, ... }: {
    systemd = {
      tmpfiles.rules = [
        "d /mnt/nas 0755 ${meta.user.username} users -"
      ];

      mounts = [
        {
          type = "cifs";
          what = "//rvn-nas/homes";
          where = "/mnt/nas";
          options = "credentials=/home/${meta.user.username}/.smbcredentials,uid=${meta.user.username},gid=users,forceuid,forcegid,iocharset=utf8,file_mode=0664,dir_mode=0775,vers=3.0";
          wantedBy = [ "multi-user.target" ];
        }
      ];

      automounts = [
        {
          where = "/mnt/nas";
          wantedBy = [ "multi-user.target" ];
          automountConfig = {
            TimeoutIdleSec = "30s";
          };
        }
      ];
    };
  };
}
