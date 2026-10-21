{ config, inputs, ... }:
let
  flakeConfig = config;
in
{
  perSystem = { lib, pkgs, ... }: {
    checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      nas-nfs-cache = pkgs.testers.runNixOSTest {
        name = "nas-nfs-cache";
        nodes = {
          server = {
            networking.interfaces.eth1.ipv4.addresses = lib.mkForce [
              { address = flakeConfig.flake.meta.nas.ipAddress; prefixLength = 24; }
            ];
            networking.firewall.allowedTCPPorts = [ 2049 ];
            users.groups.nas-media.gid = flakeConfig.flake.meta.nas.mediaGroupId;
            users.users.nas-owner = {
              isSystemUser = true;
              uid = 1026;
              group = "nas-media";
            };
            systemd.tmpfiles.rules = [
              "d /srv/nfs/volume1/downloads 2770 nas-owner nas-media -"
            ];
            services.nfs.server = {
              enable = true;
              exports = ''
                /srv/nfs *(rw,sync,fsid=0,root_squash,no_subtree_check)
              '';
            };
          };

          client = { lib, ... }: {
            imports = [
              flakeConfig.flake.modules.nixos."nas/downloads"
              inputs.sops-nix.nixosModules.sops
            ];
            services = {
              nas.smbShares = [ ];
              nasDownloadsCache.sizeGiB = 1;
              journald.settings.Journal.Storage = lib.mkForce "persistent";
            };
            sops = {
              secrets = lib.mkForce { };
              templates = lib.mkForce { };
            };
            users.users.fbb = {
              isNormalUser = true;
              uid = 1000;
              group = "users";
            };
            environment.systemPackages = [ pkgs.nfs-utils ];
            virtualisation.diskSize = 2048;
          };
        };

        testScript = ''
          client.start(allow_reboot=True)
          server.start()
          server.wait_for_unit("nfs-server.service")
          server.succeed(
              "dd if=/dev/urandom of=/srv/nfs/volume1/downloads/blob bs=1M count=16 status=none; "
              "chown nas-owner:nas-media /srv/nfs/volume1/downloads/blob; "
              "chmod 0640 /srv/nfs/volume1/downloads/blob"
          )
          client.wait_for_unit("cachefilesd.service")
          with subtest("cache daemon loads its kernel module when the device is absent"):
              client.succeed(
                  "systemctl stop cachefilesd.service && "
                  "modprobe -r cachefiles && test ! -e /dev/cachefiles"
              )
              client.succeed("systemctl start cachefilesd.service && test -c /dev/cachefiles")
              client.wait_for_unit("cachefilesd.service")

          client.wait_until_succeeds("grep CacheFiles /proc/fs/fscache/caches")
          client.succeed("test $(findmnt -n -M /var/cache/fscache -o FSTYPE) = ext4")
          client.succeed("test $(stat -c %s /var/lib/nas-downloads-cache/cache.img) = 1073741824")

          with subtest("normal user can read and write through the shared NAS group"):
              assert "65537" in client.succeed("su - fbb -c 'id -G'").split()
              client.succeed(
                  "su - fbb -c 'set -eu; printf pilot > /mnt/nas/downloads/probe; "
                  "test $(cat /mnt/nas/downloads/probe) = pilot; "
                  "mv /mnt/nas/downloads/probe /mnt/nas/downloads/renamed; "
                  "rm /mnt/nas/downloads/renamed'"
              )
              client.fail("touch /mnt/nas/downloads/root-must-not-write")

          def reads():
              return int(client.succeed(
                  "awk '$1 == \"READ:\" { print $2 }' /proc/self/mountstats"
              ).strip() or "0")

          with subtest("disk cache serves repeated reads after dropping client RAM cache"):
              first = client.succeed("su - fbb -c 'sha256sum /mnt/nas/downloads/blob'")
              assert reads() > 0, "Cold read did not register NFS READ calls"
              client.succeed("sync; echo 3 > /proc/sys/vm/drop_caches")
              before = reads()
              second = client.succeed("su - fbb -c 'sha256sum /mnt/nas/downloads/blob'")
              after = reads()
              assert first == second, (first, second)
              assert after == before, f"NFS READ calls increased: {before} -> {after}"

          with subtest("cache survives a client reboot"):
              client.reboot()
              client.wait_for_unit("cachefilesd.service")
              previous_mount = client.succeed(
                  "journalctl -b -1 -u mnt-nas-downloads.mount --no-pager -o cat"
              )
              assert "Unmounted /mnt/nas/downloads." in previous_mount, previous_mount
              assert "Failed with result" not in previous_mount, previous_mount
              before = reads()
              third = client.succeed("su - fbb -c 'sha256sum /mnt/nas/downloads/blob'")
              assert third == first
              assert reads() == before, "Rebooted client fetched cached file data from NFS"
        '';
      };
    };
  };
}
