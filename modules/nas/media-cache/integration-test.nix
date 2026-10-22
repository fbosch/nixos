{ config, inputs, ... }:
let
  flakeConfig = config;
  nas = flakeConfig.flake.meta.nas;
  smbTestPassword = "media-cache-test-password";
  smbCredentialsPath = "/etc/nas-media-cache-test-smbcredentials";
in
{
  perSystem = { lib, pkgs, ... }: {
    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      nas-media-cache = pkgs.testers.runNixOSTest {
        name = "nas-media-cache";
        nodes = {
          server = { lib, ... }: {
            networking = {
              hostName = nas.hostname;
              interfaces.eth1.ipv4.addresses = lib.mkForce [
                { address = nas.ipAddress; prefixLength = 24; }
              ];
              firewall.allowedTCPPorts = [ 2049 445 ];
            };

            users = {
              groups = {
                media.gid = 65536;
                nas-media.gid = nas.mediaGroupId;
              };
              users.fbb = {
                isNormalUser = true;
                uid = 1026;
                group = "media";
                extraGroups = [ "nas-media" ];
              };
            };

            systemd.tmpfiles.rules = [
              "d /srv/nfs 0755 root root -"
              "d /srv/nfs/volume1 0755 root root -"
              "d /srv/private 0755 root root -"
              "d /srv/private/homes 0700 fbb nas-media -"
              "f /srv/private/homes/private.txt 0600 fbb nas-media - private-data"
            ] ++ map
              (share: "d /srv/nfs/volume1/${share} 2770 fbb nas-media -")
              [ "downloads" "music" "video" ];

            services.nfs.server = {
              enable = true;
              exports = ''
                /srv/nfs *(rw,sync,fsid=0,root_squash,no_subtree_check)
              '';
            };

            services.samba = {
              enable = true;
              nmbd.enable = false;
              winbindd.enable = false;
              settings = {
                global = {
                  security = "user";
                  "map to guest" = "Never";
                };
                LaCie = {
                  # The VM's alias also checks NFS/SMB interoperability for unchanged SMB clients.
                  path = "/srv/nfs/volume1/downloads";
                  "read only" = "no";
                  "valid users" = [ "fbb" ];
                  "force group" = "nas-media";
                  "create mask" = "0660";
                  "directory mask" = "2770";
                };
                homes = {
                  path = "/srv/private/homes";
                  "read only" = "no";
                  "valid users" = [ "fbb" ];
                };
              };
            };
          };

          client = { lib, pkgs, ... }: {
            imports = [
              flakeConfig.flake.modules.nixos."nas/media-cache"
              inputs.sops-nix.nixosModules.sops
            ];

            services = {
              nas.smbShares = [ "LaCie" "homes" ];
              nasMediaCache.sizeGiB = 1;
              journald.settings.Journal.Storage = lib.mkForce "persistent";
            };

            # The mount still consumes the existing SOPS template path, but this VM
            # has no SOPS secrets or rendered templates to activate.
            sops = {
              secrets = lib.mkForce { };
              templates = lib.mkForce {
                smbcredentials.path = smbCredentialsPath;
              };
            };
            environment.etc."nas-media-cache-test-smbcredentials" = {
              text = "username=fbb\npassword=${smbTestPassword}\n";
              mode = "0400";
            };

            users = {
              groups.media.gid = 65536;
              users = {
                fbb = {
                  isNormalUser = true;
                  uid = 1000;
                  group = "media";
                  extraGroups = [ "nas-media" ];
                };
                media-reader = {
                  isSystemUser = true;
                  uid = 2000;
                  group = "media";
                  extraGroups = [ "nas-media" ];
                };
              };
            };

            environment.systemPackages = with pkgs; [ nfs-utils samba ];
            virtualisation.diskSize = 2048;
          };
        };

        testScript = ''
          import shlex

          server.start()
          server.wait_for_unit("nfs-server.service", timeout=60)
          server.wait_for_unit("samba-smbd.service", timeout=60)
          server.succeed(
              "printf '%s\\n%s\\n' '${smbTestPassword}' '${smbTestPassword}' | "
              "timeout 30s smbpasswd -s -a fbb"
          )
          server.succeed(
              "set -eu; "
              "for share in downloads music video; do "
              "  dd if=/dev/urandom of=/srv/nfs/volume1/$share/cache-probe.bin "
              "    bs=1M count=16 status=none; "
              "  chown fbb:nas-media /srv/nfs/volume1/$share/cache-probe.bin; "
              "  chmod 0640 /srv/nfs/volume1/$share/cache-probe.bin; "
              "done; "
              "test $(stat -c '%u:%g' /srv/nfs/volume1/downloads) = 1026:65537"
          )

          client.start(allow_reboot=True)
          client.wait_for_unit("cachefilesd.service", timeout=60)
          with subtest("cache daemon loads its kernel module when the device is absent"):
              client.succeed(
                  "systemctl stop cachefilesd.service && "
                  "modprobe -r cachefiles && test ! -e /dev/cachefiles"
              )
              client.succeed("systemctl start cachefilesd.service && test -c /dev/cachefiles")
              client.wait_for_unit("cachefilesd.service", timeout=60)

          client.wait_for_unit("nas-downloads-cache-image.service", timeout=60)
          client.wait_for_unit("var-cache-fscache.mount", timeout=60)
          client.wait_until_succeeds(
              "grep -q CacheFiles /proc/fs/fscache/caches", timeout=30
          )
          with subtest("shared cache uses the fixed 1 GiB ext4 backing image"):
              client.succeed(
                  "test $(findmnt -n -M /var/cache/fscache -o FSTYPE) = ext4 && "
                  "test $(stat -c %s /var/lib/nas-downloads-cache/cache.img) = 1073741824"
              )

          def as_fbb(command):
              return client.succeed("su - fbb -c " + shlex.quote(command))

          def digest_as_fbb(path):
              return as_fbb("sha256sum " + shlex.quote(path)).split()[0]

          def drop_client_ram_cache():
              # This global cache eviction is intentionally confined to this disposable VM.
              client.succeed("sync; echo 3 > /proc/sys/vm/drop_caches")

          def nfs_read_calls(mountpoint):
              awk = (
                  '$1 == "device" { active = ($5 == mount) } '
                  'active && $1 == "READ:" { total += $2 } '
                  'END { print total + 0 }'
              )
              command = (
                  "awk -v mount=" + shlex.quote(mountpoint) + " " +
                  shlex.quote(awk) + " /proc/self/mountstats"
              )
              return int(client.succeed(command).strip())

          def smb_bytes_read():
              return int(client.succeed(
                  "awk '$1 == \"Bytes\" && $2 == \"read:\" { total += $3 } "
                  "END { print total + 0 }' /proc/fs/cifs/Stats"
              ).strip())

          with subtest("client identity has both shared groups but remains distinct from NAS owner"):
              groups = set(as_fbb("id -Gn").split())
              assert {"media", "nas-media"} <= groups, groups
              assert as_fbb("id -u").strip() == "1000"
              assert server.succeed(
                  "stat -c '%u:%g' /srv/nfs/volume1/downloads"
              ).strip() == "1026:65537"

          for share in ("downloads", "music", "video"):
              mountpoint = f"/mnt/nas/{share}"
              with subtest(f"normal user can CRUD the {share} NFS share"):
                  as_fbb(
                      "set -eu; umask 0002; "
                      f"mkdir {shlex.quote(mountpoint + '/crud-dir')}; "
                      f"printf '{share}-nfs' > {shlex.quote(mountpoint + '/crud-dir/probe')}; "
                      f"test \"$(cat {shlex.quote(mountpoint + '/crud-dir/probe')})\" = '{share}-nfs'; "
                      f"mv {shlex.quote(mountpoint + '/crud-dir/probe')} "
                      f"{shlex.quote(mountpoint + '/crud-dir/renamed')}; "
                      f"rm {shlex.quote(mountpoint + '/crud-dir/renamed')}; "
                      f"rmdir {shlex.quote(mountpoint + '/crud-dir')}"
                  )

          with subtest("root is denied writes to the root-squashed downloads export"):
              client.fail("touch /mnt/nas/downloads/root-squash-denied")

          with subtest("files and directories cross-read and cross-write over NFS and SMB"):
              nfs_dir = "/mnt/nas/downloads/nfs-created"
              smb_dir = "/mnt/nas/LaCie/smb-created"
              as_fbb(
                  "set -eu; umask 0002; "
                  f"mkdir {shlex.quote(nfs_dir)}; chmod 2770 {shlex.quote(nfs_dir)}; "
                  f"printf from-nfs > {shlex.quote(nfs_dir + '/probe')}; "
                  f"chmod 0660 {shlex.quote(nfs_dir + '/probe')}"
              )
              assert as_fbb(f"cat {shlex.quote(smb_dir.replace('smb-created', 'nfs-created') + '/probe')}").strip() == "from-nfs"
              as_fbb(f"printf from-smb > {shlex.quote(smb_dir.replace('smb-created', 'nfs-created') + '/probe')}")
              assert as_fbb(f"cat {shlex.quote(nfs_dir + '/probe')}").strip() == "from-smb"

              as_fbb(
                  "set -eu; umask 0002; "
                  f"mkdir {shlex.quote(smb_dir)}; "
                  f"printf from-smb > {shlex.quote(smb_dir + '/probe')}; "
                  f"chmod 0660 {shlex.quote(smb_dir + '/probe')}"
              )
              assert as_fbb(f"cat {shlex.quote(nfs_dir.replace('nfs-created', 'smb-created') + '/probe')}").strip() == "from-smb"
              as_fbb(f"printf from-nfs > {shlex.quote(nfs_dir.replace('nfs-created', 'smb-created') + '/probe')}")
              assert as_fbb(f"cat {shlex.quote(smb_dir + '/probe')}").strip() == "from-nfs"
              server.succeed(
                  "test \"$(stat -c '%u:%g' /srv/nfs/volume1/downloads/nfs-created/probe)\" = 1000:65537 && "
                  "test \"$(stat -c '%u:%g' /srv/nfs/volume1/downloads/smb-created/probe)\" = 1026:65537"
              )

          with subtest("a distinct service UID can read and write every shared media mount"):
              command = (
                  "set -eu; umask 0002; "
                  "for share in downloads music video LaCie; do "
                  "  directory=/mnt/nas/$share/service-created; "
                  "  mkdir \"$directory\"; "
                  "  printf service-data > \"$directory/probe\"; "
                  "  test \"$(cat \"$directory/probe\")\" = service-data; "
                  "  mv \"$directory/probe\" \"$directory/renamed\"; "
                  "  rm \"$directory/renamed\"; rmdir \"$directory\"; "
                  "done; "
                  "printf service-nfs > /mnt/nas/downloads/nfs-created/probe; "
                  "printf service-smb > /mnt/nas/LaCie/smb-created/probe"
              )
              client.succeed(
                  "runuser -u media-reader -- sh -c " + shlex.quote(command)
              )
              assert as_fbb("cat /mnt/nas/downloads/nfs-created/probe").strip() == "service-nfs"
              assert as_fbb("cat /mnt/nas/LaCie/smb-created/probe").strip() == "service-smb"
              assert as_fbb(
                  "stat -c '%u:%g' /mnt/nas/LaCie/smb-created/probe"
              ).strip() == "1000:65536"

          nfs_digests = {}
          for share in ("downloads", "music", "video"):
              mountpoint = f"/mnt/nas/{share}"
              probe = f"{mountpoint}/cache-probe.bin"
              with subtest(f"NFS FS-Cache serves repeated {share} reads after RAM eviction"):
                  before = nfs_read_calls(mountpoint)
                  first = digest_as_fbb(probe)
                  after = nfs_read_calls(mountpoint)
                  assert after > before, f"Cold {share} read made no NFS READ calls"
                  nfs_digests[share] = first

                  drop_client_ram_cache()
                  before = nfs_read_calls(mountpoint)
                  second = digest_as_fbb(probe)
                  after = nfs_read_calls(mountpoint)
                  assert second == first, (share, first, second)
                  assert after == before, f"Warm {share} read issued NFS READ calls: {before} -> {after}"

          with subtest("cached LaCie SMB reads are served from FS-Cache after RAM eviction"):
              smb_probe = "/mnt/nas/LaCie/cache-probe.bin"
              as_fbb(f"stat {shlex.quote(smb_probe)} >/dev/null")
              before = smb_bytes_read()
              smb_digest = digest_as_fbb(smb_probe)
              after = smb_bytes_read()
              assert after > before, "Cold SMB read transferred no file data"

              drop_client_ram_cache()
              before = smb_bytes_read()
              warm_digest = digest_as_fbb(smb_probe)
              after = smb_bytes_read()
              assert warm_digest == smb_digest, (smb_digest, warm_digest)
              assert after == before, f"Warm SMB read transferred bytes: {before} -> {after}"

          client.succeed("sync")
          client.reboot()
          client.wait_for_unit("cachefilesd.service", timeout=60)
          client.wait_for_unit("nas-downloads-cache-image.service", timeout=60)
          client.wait_for_unit("var-cache-fscache.mount", timeout=60)
          client.wait_until_succeeds(
              "grep -q CacheFiles /proc/fs/fscache/caches", timeout=30
          )
          previous_mount = client.succeed(
              "journalctl -b -1 -u mnt-nas-downloads.mount --no-pager -o cat"
          )
          assert "Unmounted /mnt/nas/downloads." in previous_mount, previous_mount
          assert "Failed with result" not in previous_mount, previous_mount
          client.succeed(
              "test $(findmnt -n -M /var/cache/fscache -o FSTYPE) = ext4 && "
              "test $(stat -c %s /var/lib/nas-downloads-cache/cache.img) = 1073741824"
          )

          for share in ("downloads", "music", "video"):
              mountpoint = f"/mnt/nas/{share}"
              with subtest(f"persisted {share} NFS cache avoids network reads after reboot"):
                  before = nfs_read_calls(mountpoint)
                  after_reboot = digest_as_fbb(f"{mountpoint}/cache-probe.bin")
                  after = nfs_read_calls(mountpoint)
                  assert after_reboot == nfs_digests[share], (share, after_reboot, nfs_digests[share])
                  assert after == before, f"Rebooted {share} read issued NFS READ calls: {before} -> {after}"

          with subtest("persisted LaCie SMB cache avoids network reads after reboot"):
              smb_probe = "/mnt/nas/LaCie/cache-probe.bin"
              as_fbb(f"stat {shlex.quote(smb_probe)} >/dev/null")
              drop_client_ram_cache()
              before = smb_bytes_read()
              after_reboot = digest_as_fbb(smb_probe)
              after = smb_bytes_read()
              assert after_reboot == smb_digest, (after_reboot, smb_digest)
              assert after == before, f"Rebooted SMB read transferred bytes: {before} -> {after}"

          with subtest("a second SMB session invalidates cached bytes and client writes still work"):
              update_file = "/tmp/media-cache-smb-update"
              server.succeed(
                  "printf 'updated-by-second-smb-session\\n' > " + shlex.quote(update_file)
              )
              expected_update = server.succeed(
                  "sha256sum " + shlex.quote(update_file)
              ).split()[0]
              server.succeed(
                  "timeout 30s smbclient //${nas.ipAddress}/LaCie "
                  "-U 'fbb%${smbTestPassword}' -c 'put "
                  + shlex.quote(update_file)
                  + " cache-probe.bin'"
              )
              drop_client_ram_cache()
              before = smb_bytes_read()
              updated = digest_as_fbb(smb_probe)
              after = smb_bytes_read()
              assert updated == expected_update, (updated, expected_update)
              assert updated != smb_digest, "SMB client retained stale cached data after a server-side SMB update"
              assert after > before, f"Invalidated SMB read transferred no bytes: {before} -> {after}"

              client_write = "/mnt/nas/LaCie/client-after-invalidation.txt"
              as_fbb(
                  f"printf client-write-after-invalidation > {shlex.quote(client_write)}"
              )
              assert as_fbb(
                  "cat /mnt/nas/downloads/client-after-invalidation.txt"
              ).strip() == "client-write-after-invalidation"
              server.succeed(
                  "test \"$(cat /srv/nfs/volume1/downloads/client-after-invalidation.txt)\" = client-write-after-invalidation"
              )

          with subtest("private SMB remains writable by fbb but inaccessible to media services"):
              assert as_fbb("cat /mnt/nas/homes/private.txt").strip() == "private-data"
              as_fbb(
                  "set -eu; printf private-write > /mnt/nas/homes/user-created; "
                  "mv /mnt/nas/homes/user-created /mnt/nas/homes/user-renamed; "
                  "rm /mnt/nas/homes/user-renamed"
              )
              client.fail(
                  "runuser -u media-reader -- cat /mnt/nas/homes/private.txt"
              )
              client.fail(
                  "runuser -u media-reader -- sh -c "
                  + shlex.quote("printf denied > /mnt/nas/homes/service-denied")
              )
              server.succeed("test ! -e /srv/private/homes/service-denied")
        '';
      };
    };
  };
}
