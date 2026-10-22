{ config, ... }:
let
  flakeConfig = config;
  # Reuse the pilot's persisted image and initializer identity when expanding the cache.
  imageDirectory = "/var/lib/nas-downloads-cache";
  imagePath = "${imageDirectory}/cache.img";
  cacheDirectory = "/var/cache/fscache";
  cacheMountUnit = "var-cache-fscache.mount";
  nfsShares = [ "downloads" "music" "video" ];
in
{
  flake.modules.nixos."nas/media-cache" =
    { config, lib, options, pkgs, ... }:
    let
      cfg = config.services.nasMediaCache;
      scriptedAddressUnits = map (name: "${name}.service") (
        lib.filter (lib.hasPrefix "network-addresses-") (builtins.attrNames config.systemd.services)
      );
      cacheImage = pkgs.writeShellApplication {
        name = "nas-downloads-cache-image";
        runtimeInputs = with pkgs; [ coreutils e2fsprogs util-linux ];
        text = builtins.readFile ./scripts/cache-image.sh;
      };
      mkNfsMount = share: {
        what = "${flakeConfig.flake.meta.nas.ipAddress}:/volume1/${share}";
        where = "/mnt/nas/${share}";
        type = "nfs";
        options = "rw,vers=4.1,proto=tcp,sec=sys,resvport,hard,retry=0,fsc,nosuid,nodev,noexec";
        unitConfig = {
          Requires = [ "network-online.target" "cachefilesd.service" ];
          # Keep static non-gateway interfaces up until NFS has unmounted.
          After = [ "network-online.target" "cachefilesd.service" ] ++ scriptedAddressUnits;
        };
        mountConfig.TimeoutSec = "30s";
      };
      mkNfsAutomount = share: {
        where = "/mnt/nas/${share}";
        wantedBy = [ "multi-user.target" ];
        automountConfig = {
          TimeoutIdleSec = if share == "video" then "0" else "30s";
          # Automount parents must be searchable before a user can trigger the mount.
          DirectoryMode = "0555";
        };
      };
    in
    {
      imports = [ flakeConfig.flake.modules.nixos.nas ];

      options.services.nasMediaCache.sizeGiB = lib.mkOption {
        type = lib.types.ints.between 1 1024;
        default = 10;
        description = "Size in GiB of the disposable, shared NFS and SMB read cache.";
      };

      config = {
        services = {
          nas = {
            smbShares = lib.mkDefault (
              lib.subtractLists nfsShares options.services.nas.smbShares.default
            );
            cachedSmbShares = lib.mkDefault [ "LaCie" ];
          };
          cachefilesd = {
            enable = lib.mkDefault true;
            cacheDir = cacheDirectory;
            extraConfig = ''
              brun 20%
              bcull 15%
              bstop 10%
              frun 10%
              fcull 7%
              fstop 3%
            '';
          };
        };

        assertions = [
          {
            assertion = lib.all (share: !(lib.elem share config.services.nas.smbShares)) nfsShares;
            message = "nas/media-cache owns the downloads, music, and video NFS mounts; they cannot also be SMB shares.";
          }
          {
            assertion = config.services.cachefilesd.enable;
            message = "nas/media-cache requires cachefilesd for its cached mounts.";
          }
        ];

        boot.supportedFilesystems = [ "cifs" "ext4" "nfs" ];
        users.groups.nas-media = {
          gid = flakeConfig.flake.meta.nas.mediaGroupId;
          members = [ flakeConfig.flake.meta.user.username ];
        };

        systemd = {
          services = {
            nas-downloads-cache-image = {
              description = "Initialize the bounded NAS media read cache";
              unitConfig.RequiresMountsFor = [ imageDirectory ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                StateDirectory = "nas-downloads-cache";
                StateDirectoryMode = "0700";
                UMask = "0077";
              };
              script = ''
                exec ${lib.getExe cacheImage} ${lib.escapeShellArg imagePath} ${toString (cfg.sizeGiB * 1024 * 1024 * 1024)}
              '';
            };

            cachefilesd = {
              bindsTo = [ cacheMountUnit ];
              after = [ cacheMountUnit ];
              # The daemon needs its device even when boot-time module loading was skipped.
              preStart = ''
                ${pkgs.kmod}/bin/modprobe cachefiles
                ${pkgs.coreutils}/bin/chmod 0700 ${cacheDirectory}
              '';
              serviceConfig.UMask = "0077";
            };
          };

          mounts = [
            {
              what = imagePath;
              where = cacheDirectory;
              type = "ext4";
              options = "loop,nosuid,nodev,noexec";
              unitConfig = {
                # This cache starts after normal local filesystems and its initializer.
                DefaultDependencies = false;
                RequiresMountsFor = [ imageDirectory ];
                Requires = [ "nas-downloads-cache-image.service" ];
                After = [ "nas-downloads-cache-image.service" ];
                Conflicts = [ "umount.target" ];
                Before = [ "umount.target" ];
              };
            }
          ] ++ map mkNfsMount nfsShares;

          automounts = map mkNfsAutomount nfsShares;
        };
      };
    };

  flake.modules.nixos.preservation =
    { lib, options, ... }:
    {
      config = lib.mkIf (options.services ? nasMediaCache) {
        preservation.preserveAt."/persist".directories = [
          {
            directory = imageDirectory;
            mode = "0700";
          }
        ];
      };
    };
}
