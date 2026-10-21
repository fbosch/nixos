{ config, ... }:
{
  perSystem =
    { lib, pkgs, system, ... }:
    let
      host = name: config.flake.nixosConfigurations.${name}.config;
      clients = map host [ "rvn-pc" "rvn-srv" ];
      downloadsMount = cfg:
        lib.findFirst (mount: mount.where == "/mnt/nas/downloads") null cfg.systemd.mounts;
      cacheMount = cfg:
        lib.findFirst (mount: mount.where == cfg.services.cachefilesd.cacheDir) null cfg.systemd.mounts;
      smbPaths = [
        "/mnt/nas/FrederikDocs"
        "/mnt/nas/LaCie"
        "/mnt/nas/backup"
        "/mnt/nas/cloud-backup"
        "/mnt/nas/encrypted"
        "/mnt/nas/homes"
        "/mnt/nas/music"
        "/mnt/nas/photo"
        "/mnt/nas/video"
        "/mnt/nas/web"
        "/mnt/nas/websites"
      ];
      server = host "rvn-srv";
      mediaUsers = [ "plex" "bazarr" "prowlarr" "lidarr" "radarr" "sonarr" ];
    in
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        nas-cache-image = pkgs.runCommand "nas-cache-image-tests"
          {
            nativeBuildInputs = with pkgs; [ python3 bash coreutils e2fsprogs util-linux ];
          } ''
          python ${./__tests__/cache-image.py} ${./scripts/cache-image.sh}
          touch "$out"
        '';
      };

      nix-unit.tests.nasDownloads = lib.optionalAttrs (system == "x86_64-linux") {
        testBothHostsUseCachedReadWriteNfs = {
          expr = map
            (cfg:
              let mount = downloadsMount cfg;
              in {
                inherit (mount) type what;
                options = lib.splitString "," mount.options;
              }
            )
            clients;
          expected = lib.replicate 2 {
            type = "nfs";
            what = "192.168.1.2:/volume1/downloads";
            options = [ "rw" "vers=4.1" "proto=tcp" "sec=sys" "resvport" "hard" "retry=0" "fsc" "nosuid" "nodev" "noexec" ];
          };
        };

        testRemainingSharesKeepSmbOnBothHosts = {
          expr = map
            (cfg:
              builtins.sort builtins.lessThan (
                map (mount: mount.where)
                  (builtins.filter (mount: mount.type == "cifs") cfg.systemd.mounts)
              )
            )
            clients;
          expected = [ smbPaths smbPaths ];
        };

        testVirtualMachineKeepsItsSmbDownloads = {
          expr = let mount = downloadsMount (host "rvn-vm"); in {
            inherit (mount) type what;
          };
          expected = {
            type = "cifs";
            what = "//rvn-nas/downloads";
          };
        };

        testClientIdentityUsesSharedGroupWithoutChangingUserIds = {
          expr = map
            (cfg: {
              gid = cfg.users.groups.nas-media.gid;
              uid = cfg.users.users.fbb.uid;
              member = lib.elem "fbb" cfg.users.groups.nas-media.members;
            })
            clients;
          expected = [
            { gid = 65537; uid = 1000; member = true; }
            { gid = 65537; uid = null; member = true; }
          ];
        };

        testMediaServicesAndContainerUseNasMediaGroup = {
          expr = {
            services = map (name: lib.elem "nas-media" server.users.users.${name}.extraGroups) mediaUsers;
            containerGid = server.services.rdtclient.groupId;
          };
          expected = {
            services = lib.replicate (builtins.length mediaUsers) true;
            containerGid = 65537;
          };
        };

        testCacheImagesHaveHostSpecificCaps = {
          expr = map (cfg: cfg.services.nasDownloadsCache.sizeGiB) clients;
          expected = [ 20 10 ];
        };

        testCacheUsesDiskBackedExt4AndInitializesBeforeMounting = {
          expr = map
            (cfg:
              let mount = cacheMount cfg;
              in {
                inherit (mount) type what;
                initializer = mount.unitConfig.Requires;
                sourceMounts = cfg.systemd.services.nas-downloads-cache-image.unitConfig.RequiresMountsFor;
                stateDirectory = cfg.systemd.services.nas-downloads-cache-image.serviceConfig.StateDirectory;
              }
            )
            clients;
          expected = lib.replicate 2 {
            type = "ext4";
            what = "/var/lib/nas-downloads-cache/cache.img";
            initializer = [ "nas-downloads-cache-image.service" ];
            sourceMounts = [ "/var/lib/nas-downloads-cache" ];
            stateDirectory = "nas-downloads-cache";
          };
        };

        testNfsMountRequiresTheCacheDaemon = {
          expr = map (cfg: (downloadsMount cfg).unitConfig.Requires) clients;
          expected = lib.replicate 2 [ "network-online.target" "cachefilesd.service" ];
        };

        testCacheImagePersistsOnTmpfsRootHost = {
          expr = lib.any
            (directory:
              directory.directory == "/var/lib/nas-downloads-cache" && directory.mode == "0700"
            )
            (host "rvn-pc").preservation.preserveAt."/persist".directories;
          expected = true;
        };

        testContainerRequiresItsDownloadMounts = {
          expr = lib.all
            (line:
              lib.hasInfix line server.environment.etc."containers/systemd/rdtclient.container".text
            ) [ "RequiresMountsFor=/mnt/nas/downloads\n" "RequiresMountsFor=/mnt/nas/downloads/rdtclient-temp\n" ];
          expected = true;
        };
      };
    };
}
