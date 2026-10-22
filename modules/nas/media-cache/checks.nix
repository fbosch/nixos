{ config, ... }:
{
  perSystem =
    { lib, pkgs, system, ... }:
    let
      host = name: config.flake.nixosConfigurations.${name}.config;
      clients = map host [ "rvn-pc" "rvn-srv" ];
      nfsShares = [ "downloads" "music" "video" ];
      cachedShares = nfsShares ++ [ "LaCie" ];
      privateShares = [ "FrederikDocs" "backup" "cloud-backup" "encrypted" "homes" "photo" "web" "websites" ];
      mountFor = cfg: share:
        lib.findFirst (mount: mount.where == "/mnt/nas/${share}") null cfg.systemd.mounts;
      cacheMount = cfg:
        lib.findFirst (mount: mount.where == cfg.services.cachefilesd.cacheDir) null cfg.systemd.mounts;
      optionsFor = mount: lib.splitString "," mount.options;
      smbPaths = map (share: "/mnt/nas/${share}") [ "FrederikDocs" "LaCie" "backup" "cloud-backup" "encrypted" "homes" "photo" "web" "websites" ];
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

      nix-unit.tests.nasMediaCache = lib.optionalAttrs (system == "x86_64-linux") {
        testBothHostsUseCachedReadWriteNfsForVerifiedShares = {
          expr = map
            (cfg: map
              (share:
                let mount = mountFor cfg share;
                in {
                  inherit (mount) type what;
                  options = optionsFor mount;
                }
              )
              nfsShares
            )
            clients;
          expected = lib.replicate 2 (map
            (share: {
              type = "nfs";
              what = "192.168.1.2:/volume1/${share}";
              options = [ "rw" "vers=4.1" "proto=tcp" "sec=sys" "resvport" "hard" "retry=0" "fsc" "nosuid" "nodev" "noexec" ];
            })
            nfsShares);
        };

        testLacieUsesStrictCachedSmbWithoutChangingItsIdentityMapping = {
          expr = map
            (cfg:
              let mount = mountFor cfg "LaCie";
              in {
                inherit (mount) type what;
                options = optionsFor mount;
                enabledShares = cfg.services.nas.cachedSmbShares;
              }
            )
            clients;
          expected = map
            (cfg: {
              type = "cifs";
              what = "//rvn-nas/LaCie";
              options = [
                "credentials=${cfg.sops.templates.smbcredentials.path}"
                "uid=fbb"
                "gid=media"
                "forceuid"
                "forcegid"
                "iocharset=utf8"
                "file_mode=0660"
                "dir_mode=0770"
                "vers=3.1.1"
                "cache=strict"
                "fsc"
              ];
              enabledShares = [ "LaCie" ];
            })
            clients;
        };

        testUnconvertedSharesKeepSmbOnBothHosts = {
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

        testPrivateSharesKeepUserOnlyUncachedSmbAccess = {
          expr = map
            (cfg: lib.all
              (share:
                let mount = mountFor cfg share; options = optionsFor mount;
                in mount.type == "cifs"
                  && lib.elem "gid=users" options
                  && lib.elem "uid=fbb" options
                  && lib.elem "file_mode=0660" options
                  && lib.elem "dir_mode=0770" options
                  && !(lib.elem "fsc" options)
                  && !(lib.elem "cachefilesd.service" mount.unitConfig.Requires)
              )
              privateShares
            )
            clients;
          expected = [ true true ];
        };

        testVirtualMachineKeepsItsUncachedSmbMediaMounts = {
          expr = map
            (share:
              let mount = mountFor (host "rvn-vm") share;
              in {
                inherit (mount) type what;
                cached = lib.elem "fsc" (optionsFor mount);
              }
            )
            cachedShares;
          expected = map (share: { type = "cifs"; what = "//rvn-nas/${share}"; cached = false; }) cachedShares;
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

        testMediaServicesAndContainerKeepSharedNasAccess = {
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
          expr = map (cfg: cfg.services.nasMediaCache.sizeGiB) clients;
          expected = [ 20 10 ];
        };

        testOneDiskBackedCacheReusesThePilotImageAndInitializer = {
          expr = map
            (cfg:
              let mount = cacheMount cfg;
              in {
                inherit (mount) type what;
                initializer = mount.unitConfig.Requires;
                sourceMounts = cfg.systemd.services.nas-downloads-cache-image.unitConfig.RequiresMountsFor;
                stateDirectory = cfg.systemd.services.nas-downloads-cache-image.serviceConfig.StateDirectory;
                daemonMask = cfg.systemd.services.cachefilesd.serviceConfig.UMask;
              }
            )
            clients;
          expected = lib.replicate 2 {
            type = "ext4";
            what = "/var/lib/nas-downloads-cache/cache.img";
            initializer = [ "nas-downloads-cache-image.service" ];
            sourceMounts = [ "/var/lib/nas-downloads-cache" ];
            stateDirectory = "nas-downloads-cache";
            daemonMask = "0077";
          };
        };

        testAllCachedMountsRequireAndFollowTheSameDaemon = {
          expr = map
            (cfg: map
              (share:
                let mount = mountFor cfg share;
                in {
                  requires = mount.unitConfig.Requires;
                  followsDaemon = lib.elem "cachefilesd.service" mount.unitConfig.After;
                }
              )
              cachedShares
            )
            clients;
          expected = lib.replicate 2 (lib.replicate 4 {
            requires = [ "network-online.target" "cachefilesd.service" ];
            followsDaemon = true;
          });
        };

        testVideoMountKeepsPersistentAutomountAndSearchableNfsParents = {
          expr = map
            (cfg: map
              (share:
                let auto = lib.findFirst (mount: mount.where == "/mnt/nas/${share}") null cfg.systemd.automounts;
                in { inherit (auto.automountConfig) TimeoutIdleSec DirectoryMode; }
              )
              nfsShares
            )
            clients;
          expected = lib.replicate 2 [
            { TimeoutIdleSec = "30s"; DirectoryMode = "0555"; }
            { TimeoutIdleSec = "30s"; DirectoryMode = "0555"; }
            { TimeoutIdleSec = "0"; DirectoryMode = "0555"; }
          ];
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
