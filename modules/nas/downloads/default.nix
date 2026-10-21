{ config, ... }:
let
  flakeConfig = config;
  imageDirectory = "/var/lib/nas-downloads-cache";
  imagePath = "${imageDirectory}/cache.img";
  cacheDirectory = "/var/cache/fscache";
  cacheMountUnit = "var-cache-fscache.mount";
in
{
  flake.modules.nixos."nas/downloads" =
    { config, lib, options, pkgs, ... }:
    let
      cfg = config.services.nasDownloadsCache;
      scriptedAddressUnits = map (name: "${name}.service") (
        lib.filter (lib.hasPrefix "network-addresses-") (builtins.attrNames config.systemd.services)
      );
      cacheImage = pkgs.writeShellApplication {
        name = "nas-downloads-cache-image";
        runtimeInputs = with pkgs; [ coreutils e2fsprogs util-linux ];
        text = builtins.readFile ./scripts/cache-image.sh;
      };
    in
    {
      imports = [ flakeConfig.flake.modules.nixos.nas ];

      options.services.nasDownloadsCache.sizeGiB = lib.mkOption {
        type = lib.types.ints.between 1 1024;
        default = 10;
        description = "Size in GiB of the disposable, loop-backed NFS read cache.";
      };

      config = {
        services = {
          nas.smbShares = lib.mkDefault (
            lib.remove "downloads" options.services.nas.smbShares.default
          );
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
            assertion = !(lib.elem "downloads" config.services.nas.smbShares);
            message = "nas/downloads owns /mnt/nas/downloads; it cannot also be an SMB share.";
          }
          {
            assertion = config.services.cachefilesd.enable;
            message = "nas/downloads requires cachefilesd for its cached NFS mount.";
          }
        ];

        boot.supportedFilesystems = [ "ext4" "nfs" ];
        users = {
          groups.nas-media = {
            gid = flakeConfig.flake.meta.nas.mediaGroupId;
            members = [ flakeConfig.flake.meta.user.username ];
          };
        };

        systemd = {
          services = {
            nas-downloads-cache-image = {
              description = "Initialize the bounded NAS downloads read cache";
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
              preStart = "${pkgs.coreutils}/bin/chmod 0700 ${cacheDirectory}";
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
            {
              what = "${flakeConfig.flake.meta.nas.ipAddress}:/volume1/downloads";
              where = "/mnt/nas/downloads";
              type = "nfs";
              options = "rw,vers=4.1,proto=tcp,sec=sys,resvport,hard,retry=0,fsc,nosuid,nodev,noexec";
              unitConfig = {
                Requires = [ "network-online.target" "cachefilesd.service" ];
                # Keep static non-gateway interfaces up until NFS has unmounted.
                After = [ "network-online.target" "cachefilesd.service" ] ++ scriptedAddressUnits;
              };
              mountConfig.TimeoutSec = "30s";
            }
          ];

          automounts = [
            {
              where = "/mnt/nas/downloads";
              wantedBy = [ "multi-user.target" ];
              automountConfig = {
                TimeoutIdleSec = "30s";
                # Automount parents must be searchable before a user can trigger the mount.
                DirectoryMode = "0555";
              };
            }
          ];
        };
      };
    };

  flake.modules.nixos.preservation =
    { lib, options, ... }:
    {
      config = lib.mkIf (options.services ? nasDownloadsCache) {
        preservation.preserveAt."/persist".directories = [
          {
            directory = imageDirectory;
            mode = "0700";
          }
        ];
      };
    };
}
