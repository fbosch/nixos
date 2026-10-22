{ config, ... }:
{
  perSystem = { lib, pkgs, system, ... }:
    let
      host = name: config.flake.nixosConfigurations.${name}.config;
      clients = map host [ "rvn-pc" "rvn-srv" ];
      nfsShares = [ "downloads" "music" "video" ];
      mediaShares = nfsShares ++ [ "LaCie" ];
      cachedSmbShares = [ "LaCie" "FrederikDocs" ];
      privateShares = [ "FrederikDocs" "backup" "cloud-backup" "encrypted" "homes" "photo" "web" "websites" ];
      mountFor = cfg: path: lib.findFirst (mount: mount.where == path) null cfg.systemd.mounts;
      optionsFor = mount: lib.splitString "," mount.options;
      hasOptions = required: mount: lib.all (option: lib.elem option (optionsFor mount)) required;
      cachedMount = mount: mount != null
        && !(lib.elem "ro" (optionsFor mount))
        && lib.all (unit: lib.elem unit mount.unitConfig.Requires && lib.elem unit mount.unitConfig.After)
        [ "network-online.target" "cachefilesd.service" ];
      clientHealthy = name: size:
        let
          cfg = host name;
          cache = mountFor cfg "/var/cache/fscache";
        in
        cfg.services.cachefilesd.enable
        && cfg.services.cachefilesd.cacheDir == "/var/cache/fscache"
        && cfg.services.nasMediaCache.sizeGiB == size
        && cache != null && cache.type == "ext4"
        && cache.what == "/var/lib/nas-downloads-cache/cache.img"
        && hasOptions [ "loop" "nosuid" "nodev" "noexec" ] cache
        && lib.elem "nas-downloads-cache-image.service" cache.unitConfig.Requires
        && cfg.systemd.services.nas-downloads-cache-image.serviceConfig.StateDirectory == "nas-downloads-cache"
        && cfg.systemd.services.nas-downloads-cache-image.serviceConfig.StateDirectoryMode == "0700"
        && cfg.systemd.services.nas-downloads-cache-image.unitConfig.RequiresMountsFor == [ "/var/lib/nas-downloads-cache" ]
        && cfg.systemd.services.cachefilesd.serviceConfig.UMask == "0077"
        && lib.all
          (share:
            let mount = mountFor cfg "/mnt/nas/${share}";
            in cachedMount mount && mount.type == "nfs"
            && mount.what == "192.168.1.2:/volume1/${share}"
            && hasOptions [ "rw" "vers=4.1" "proto=tcp" "sec=sys" "resvport" "hard" "retry=0" "fsc" "nosuid" "nodev" "noexec" ] mount
          )
          nfsShares
        && lib.all
          (share:
            let mount = mountFor cfg "/mnt/nas/${share}";
            in cachedMount mount && mount.type == "cifs" && mount.what == "//rvn-nas/${share}"
            && hasOptions [ "credentials=${cfg.sops.templates.smbcredentials.path}" "iocharset=utf8" "uid=fbb" "gid=${if share == "LaCie" then "media" else "users"}" "forceuid" "forcegid" "file_mode=0660" "dir_mode=0770" "vers=3.1.1" "cache=strict" "fsc" ] mount
            && !(lib.elem "cache=loose" (optionsFor mount))
          )
          cachedSmbShares
        && cfg.services.nas.cachedSmbShares == cachedSmbShares;
      server = host "rvn-srv";
      requirements = {
        "rvn-pc cached mounts" = clientHealthy "rvn-pc" 20;
        "rvn-srv cached mounts" = clientHealthy "rvn-srv" 10;
        "unconverted SMB access" = lib.all
          (cfg:
            builtins.sort builtins.lessThan cfg.services.nas.smbShares
            == builtins.sort builtins.lessThan (privateShares ++ [ "LaCie" ])
            && lib.all
              (share:
                let mount = mountFor cfg "/mnt/nas/${share}";
                in mount != null && mount.type == "cifs"
                && hasOptions [ "uid=fbb" "gid=users" "file_mode=0660" "dir_mode=0770" ] mount
                && lib.elem "fsc" (optionsFor mount) == (share == "FrederikDocs")
                && lib.elem "cachefilesd.service" mount.unitConfig.Requires == (share == "FrederikDocs")
              )
              privateShares
          )
          clients;
        "rvn-vm SMB mounts" = lib.all
          (share:
            let mount = mountFor (host "rvn-vm") "/mnt/nas/${share}";
            in mount != null && mount.type == "cifs" && mount.what == "//rvn-nas/${share}"
              && !(lib.elem "fsc" (optionsFor mount))
          )
          (mediaShares ++ [ "FrederikDocs" ]);
        "media identities" = lib.all
          (cfg: cfg.users.groups.nas-media.gid == 65537
            && lib.elem "fbb" cfg.users.groups.nas-media.members
            && (cfg.users.users.fbb.uid == null || cfg.users.users.fbb.uid == 1000)
          )
          clients
        && lib.all (name: lib.elem "nas-media" server.users.users.${name}.extraGroups)
          [ "plex" "bazarr" "prowlarr" "lidarr" "radarr" "sonarr" ]
        && server.services.rdtclient.groupId == 65537;
        "NFS automount access" = lib.all
          (cfg: lib.all
            (share:
              let mount = lib.findFirst (mount: mount.where == "/mnt/nas/${share}") null cfg.systemd.automounts;
              in mount != null && mount.automountConfig.DirectoryMode == "0555"
                && mount.automountConfig.TimeoutIdleSec == (if share == "video" then "0" else "30s")
            )
            nfsShares
          )
          clients;
        "persistent cache" = lib.any
          (directory: directory.directory == "/var/lib/nas-downloads-cache" && directory.mode == "0700")
          (host "rvn-pc").preservation.preserveAt."/persist".directories;
        "container NAS access" = lib.all
          (line: lib.hasInfix line server.environment.etc."containers/systemd/rdtclient.container".text)
          [ "RequiresMountsFor=/mnt/nas/downloads\n" "RequiresMountsFor=/mnt/nas/downloads/rdtclient-temp\n" "SupplementaryGroups=65537\n" ];
      };
      failures = lib.attrNames (lib.filterAttrs (_: healthy: !healthy) requirements);
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        nas-media-cache = assert lib.assertMsg (failures == [ ])
          "NAS smoke check failed: ${lib.concatStringsSep ", " failures}";
          pkgs.runCommand "nas-media-cache-smoke"
            { nativeBuildInputs = with pkgs; [ python3 bash coreutils e2fsprogs util-linux ]; }
            ''
              python -I - ${./scripts/cache-image.sh} <<'PY'
              import hashlib
              import subprocess
              import sys
              import tempfile
              from pathlib import Path

              size = 64 * 1024 * 1024
              with tempfile.TemporaryDirectory() as temporary:
                  directory = Path(temporary)
                  image = directory / "cache.img"

                  def initialize(capacity=size, succeeds=True):
                      result = subprocess.run(
                          ["bash", sys.argv[1], str(image), str(capacity)],
                          capture_output=True, text=True,
                      )
                      assert (result.returncode == 0) == succeeds, f"expected success={succeeds}; exit={result.returncode}: {result.stderr}"
                      return result

                  def digest():
                      return hashlib.sha256(image.read_bytes()).digest()

                  initialize()
                  assert image.stat().st_size == size
                  assert image.stat().st_mode & 0o777 == 0o600
                  filesystem = subprocess.check_output(
                      ["blkid", "-p", "-s", "TYPE", "-o", "value", str(image)], text=True,
                  ).strip()
                  assert filesystem == "ext4"
                  assert list(directory.iterdir()) == [image]

                  original = digest()
                  initialize()
                  assert digest() == original
                  result = initialize(size * 2, succeeds=False)
                  assert "size changed" in result.stderr
                  assert digest() == original

                  image.unlink()
                  with image.open("wb") as file:
                      file.truncate(size)
                  original = digest()
                  initialize(succeeds=False)
                  assert digest() == original

                  image.unlink()
                  target = directory / "existing-data"
                  target.write_bytes(b"unrelated data")
                  image.symlink_to(target)
                  initialize(succeeds=False)
                  assert image.is_symlink()
                  assert target.read_bytes() == b"unrelated data"

                  image.unlink()
                  image.mkdir()
                  initialize(succeeds=False)
                  assert image.is_dir()
                  assert list(image.iterdir()) == []
              PY
              touch "$out"
            '';
      };
    };
}
