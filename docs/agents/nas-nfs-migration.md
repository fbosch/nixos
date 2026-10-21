# Downloads NFS pilot

`nas/downloads` replaces only `/mnt/nas/downloads` on `rvn-pc` and `rvn-srv`.
The other shares and all mounts on `rvn-vm` stay on SMB.

## Access

The client mounts `192.168.1.2:/volume1/downloads` using NFSv4.1 and `sec=sys`.
The NAS must allow both client IPs, use **Map root to guest**, and grant the
`nas-media` group read/write access to `downloads`. Its GID is `65537` on the
NAS and both clients. Apply the share ACL to existing children and enable
inheritance for new files and directories. Do not use **Map all users to admin**.

`fbb` joins `nas-media` without changing its UID or primary group. On `rvn-srv`,
Plex and the enabled Servarr services gain supplementary membership. Their
existing `media` group remains unchanged. RDT-Client uses UID `1000` and primary
GID `65537`. This role does not grant access to private NAS shares.

Before switching, verify normal-user create, read, write, rename, and delete
operations with GID `65537` on the temporary NFS pilot mount. Confirm new files
retain the caller's UID rather than NAS admin UID `1024`. On `rvn-srv`, also
verify a media service UID can access files created by the download identity.
A successful test under the old admin mapping does not verify this setup.

## Cache storage

| Host | Image capacity | Backing storage |
| --- | --- | --- |
| `rvn-pc` | 20 GiB | `/persist/var/lib/nas-downloads-cache/cache.img` |
| `rvn-srv` | 10 GiB | `/var/lib/nas-downloads-cache/cache.img` |

Both hosts expose the image at `/var/lib/nas-downloads-cache/cache.img` and mount
its ext4 filesystem at `/var/cache/fscache`. On `rvn-pc`, preservation binds the
image directory from `/persist`, so neither the image nor cached data uses the
tmpfs root. The ext4 image provides CacheFiles support over the Btrfs backing
filesystem. The sparse image grows as the cache fills, up to its configured
capacity. Filesystem metadata and cache eviction thresholds reduce usable space.

The cache contains downloaded file contents. Its image directory and mounted
root are restricted to root. FS-Cache accelerates repeated reads, not first reads
or writes. NFS writes go to the NAS. Cached data is disposable and does not
provide offline access or a backup.

Startup ordering is image initialization, ext4 mount, `cachefilesd`, then NFS.
RDT-Client requires its download mounts before starting. The initializer reuses
an existing ext4 image but refuses symlinks, other file types, unrecognized
filesystems, and size changes. It never reformats an existing image.

## Switch one host at a time

1. Complete the NAS mapping and identity checks above. Pause download activity
   and stop services or other processes using `/mnt/nas/downloads` on that host.
2. Stop `mnt-nas-downloads.automount` and `mnt-nas-downloads.mount` with `sudo
   systemctl stop`. Do not force or lazy-unmount a busy filesystem. On `rvn-pc`,
   unmount `/mnt/nfs-pilot` after finishing the permission checks.
3. Rebuild from a checkout containing these changes. New files under
   `modules/nas/downloads/` must be in Git's index for a Git-backed flake to see
   them; a commit is not required. Switching the system needs `sudo`.
4. Start a fresh `fbb` login so it receives the new group membership. Access
   `/mnt/nas/downloads`, verify its active filesystem is NFSv4 with `fsc`, and
   confirm `/var/cache/fscache` is ext4. Check `cachefilesd` and the image
   initializer for failures.
5. Repeat the permission checks, restart the stopped services, and verify their
   downloads and imports. Then repeat the cutover on the other host.

Host evaluation and VM tests do not verify the live Synology ACLs, current NFS
mapping, or application access. Keep the live cutover pending until those checks
pass on both hosts.

## Resizing or discarding the cache

Change `services.nasDownloadsCache.sizeGiB` only during a cache maintenance
window. Stop consumers and the downloads automount/mount, stop `cachefilesd`,
and unmount `/var/cache/fscache` before replacing its disposable image. Stop the
image initializer too, so its completed oneshot state cannot skip initialization.
Never remove or resize an image while its loop filesystem is mounted. Do not
remove anything under `/mnt/nas/downloads` when resetting the local cache.
