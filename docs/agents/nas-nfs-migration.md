# Cached NAS media mounts

`nas/media-cache` configures one shared read cache on `rvn-pc` and `rvn-srv`.
Activation and live application checks remain separate from building this configuration.

| Shares | Protocol on `rvn-pc` and `rvn-srv` | Read cache |
| --- | --- | --- |
| `downloads`, `music`, `video` | NFSv4.1 | FS-Cache |
| `LaCie`, `FrederikDocs` | SMB 3.1.1 with `cache=strict` | FS-Cache |
| Other shares | Existing SMB configuration | Unchanged |

All mounts on `rvn-vm` retain their existing SMB configuration without FS-Cache.
The mount paths stay `/mnt/nas/<share>`. Cached mounts remain read/write.

## NFS access

The NFS exports are `192.168.1.2:/volume1/{downloads,music,video}` with `sec=sys`.
The NAS must allow `192.168.1.169` and `192.168.1.46`, use **Map root to guest**,
and grant `nas-media` read/write access. Its GID is `65537` on the NAS and both
clients. Existing data and newly created children must inherit the media ACL.
Do not use **Map all users to admin**.

`fbb` joins `nas-media` without changing its UID or primary group. On `rvn-srv`,
Plex and the enabled Servarr services gain supplementary membership. Their
existing `media` group remains unchanged. RDT-Client runs rootless as `fbb`, UID
`1000`, retaining supplementary GID `65537` through `crun`'s `keep-groups`.
Its primary group stays `users`. Private shares retain their user-only SMB mounts.

Temporary preflights passed create/read/write/rename/delete checks and the
12-file existing-data samples for the three Volume 1 shares on both hosts.
The server checks modeled the planned service group membership; they do not
prove that running services have received it. Root creation was denied on all
three exports. Recheck access after activation, including downloads and imports.

## Rootless RDT-Client

The system `rdtclient.service` remains the startup-policy entry point. It requires
the NAS mounts and `user@1000.service`, then starts and observes the user Quadlet.
The user unit is not enabled independently: `/run/rdtclient/ready` guards it until
the system controller has prepared the mounts and database. Stopping the system
controller stops the user unit before releasing its mount dependencies.
Changes to the user Quadlet also trigger a controller restart during a system
switch.

The pinned `2.0.142` image runs `dotnet RdtClient.Web.dll` directly. Its stock s6
launcher resets supplementary groups and recursively changes ownership of `/data`
unless `SKIP_CHOWN=true`. The rootless unit bypasses that launcher and sets
`SKIP_CHOWN=true`; do not add ownership-changing bind options. Retest the direct
entry point and group retention when upgrading the image.

Keep seccomp-based systemd restrictions off the user-unit launcher: unprivileged
systemd applies them with `no_new_privs`, preventing Nix's `newuidmap` and
`newgidmap` wrappers from gaining their required capabilities. This fails with a
fresh Podman namespace even if a pre-existing namespace made earlier probes pass.
Container-level `NoNewPrivileges`, capability drops, and read-only root remain
in place. Validate helper execution in the generated unit's sandbox and namespace
bootstrap with isolated Podman storage; do not rely on a warm user namespace.

The existing database stays at `/var/lib/rdtclient/data/rdtclient.db`, with no
recursive ownership changes. The local data directory becomes `0700`. Before the
first rootless start, the controller stops the user unit and atomically publishes
a private, non-overwriting `rdtclient.pre-rootless.db` copy. A nonempty SQLite WAL
or journal blocks that first backup. If blocked, create a consistent SQLite backup
at that filename before retrying; do not delete journal files. The account is
pinned to its existing UID `1000`, with lingering enabled declaratively.

HTTP health gates startup. Only the system controller retries failures, with the
shared limit of three attempts per hour and a 60-second restart delay. Container
shutdown gets 60 seconds, the user unit 75 seconds, and the controller 90 seconds.
Verify graceful shutdown with a disposable database copy before activation.

On `rvn-srv`, inspect the controller with `systemctl status rdtclient` and the
container unit with `systemctl --user status rdtclient` as `fbb`. Reset a controller
start limit with `sudo systemctl reset-failed rdtclient`, then start it with
`sudo systemctl start rdtclient`. Do not start the user unit independently.

## Why LaCie stays on SMB

LaCie is the ext4 USB filesystem at `/volumeUSB1/usbshare`. Its export correctly
squashed root to guest UID `1025`, GID `100`, but its `0777` root allowed guest
writes. Its existing `downloads` and `videos` directories were also `0777` and
owned by NAS `fbb`, UID `1026`, group `100`. NFS-created directories were `0755`,
owned by client UID `1000`, group `100`, so other service UIDs could not write.

The inspected directories reported Linux mode with no Synology ACL archive
flags. The `synoacl` mount option alone did not provide inheritance. The NAS
had no `getfacl` or `setfacl` in its system PATH; POSIX ACL capability was not
established. Synology also [excludes USB shares from Windows ACL management](https://kb.synology.com/en-us/DSM/help/DSM/AdminCenter/file_share_privilege).

SMB retains the existing NAS credentials and local `forceuid`/`forcegid`
presentation. Adding `fsc,cache=strict` does not change NAS ownership or require
recursive permission changes. It does not make the mount read-only. Do not
use `cache=loose` with these shared, concurrently written files.

LaCie also contains `backup.hbk`. Do not apply media permissions recursively
across the USB root or change backup ownership. Caching does not narrow the
existing SMB access scope or make backup data private from an identity that
already has access to the share.

Remove the provisional LaCie NFS rules for the two clients when adopting this
hybrid configuration. Keep the three Volume 1 NFS exports unchanged.

## Private document caching

FrederikDocs stays on SMB with its existing credentials, `uid=fbb`, `gid=users`,
and `0660`/`0770` file/directory modes. Only its caching and daemon dependencies
change; NAS permissions and media-group access remain unchanged. Other private
shares remain uncached.

Document contents read from FrederikDocs can persist in the host's shared cache.
The image is `0600` and its directory and mounted cache root are `0700`, but
FS-Cache adds no encryption. The configuration declares LUKS backing for
`rvn-pc`; it declares none for `rvn-srv`. Verify live backing-storage protection
on both hosts before activating private-document caching.

## Cache storage

| Host | Shared image capacity | Backing storage |
| --- | --- | --- |
| `rvn-pc` | 20 GiB | `/persist/var/lib/nas-downloads-cache/cache.img` |
| `rvn-srv` | 10 GiB | `/var/lib/nas-downloads-cache/cache.img` |

These are per-host limits shared by all five cached mounts, not per-share limits.
The original image path and `nas-downloads-cache-image.service` identity remain
so the hybrid setup reuses the pilot cache instead of allocating another image.

Both hosts expose the image at `/var/lib/nas-downloads-cache/cache.img` and mount
its ext4 filesystem at `/var/cache/fscache`. On `rvn-pc`, preservation binds the
image directory from `/persist`, keeping cached data off the tmpfs root. The
ext4 image provides CacheFiles support over the Btrfs backing filesystem. It
is sparse and grows up to its capacity. Metadata and eviction thresholds
reduce usable space.

The cache holds contents read through the cached mounts. Its image directory
and mounted root are restricted to root. Repeat reads may use the local disk;
first reads and writes still need the NAS. This is not offline storage or a
backup. SMB retains strict lease/oplock-based cache coherency.

Startup ordering is image initialization, ext4 mount, `cachefilesd`, then the
cached NFS and SMB mounts. All five mounts require the same daemon. RDT-Client
requires its download mounts before starting. The initializer reuses an existing
ext4 image but refuses symlinks, other file types, unrecognized filesystems,
and size changes. It never reformats an existing image.

## Build-time smoke check

Run `nix build --no-link .#checks.x86_64-linux.nas-media-cache`.
This is the single default NAS check. It validates the configured mounts, cache
limits, access groups, and startup dependencies, then exercises the real image
initializer with temporary files. It needs no NAS mounts or decrypted credentials.
It does not prove live permissions, cache hits, or invalidation.

The last VM run failed when reading an SMB-created file over SMB after modifying
it over NFS. Whether this also affects the Synology configuration is unknown.

TODO(nas/media-cache maintainer, before hybrid activation): verify cross-protocol
coherency against the NAS and resolve any failure. Writes through NFS must become
visible through SMB, and vice versa. A passing smoke check is not clearance to
activate the hybrid mounts.

## Switch one host at a time

1. Pass the smoke check and resolve the coherency activation gate first.
   Git-backed flakes need new files under `modules/nas/media-cache/` in the
   index; a commit is not required.
2. Remove only the provisional LaCie NFS client rules above. Do not change NAS
   file ownership, USB permissions, or the Volume 1 exports.
3. Pause activity and stop services or processes using `downloads`, `music`,
   `video`, `LaCie`, and `FrederikDocs` on the target host. Stop their automount
   and mount units with `sudo systemctl stop`. Do not force or lazy-unmount a
   busy filesystem.
   Remove temporary pilot mounts after finishing their access checks.
4. Switch the target host to the new configuration with `sudo`. Start a fresh
   `fbb` login and restart stopped services so they receive current groups.
5. Trigger all five mounts. Verify NFSv4.1 with `fsc` for the Volume 1 shares and
   SMB 3.1.1 with `cache=strict,fsc` for LaCie and FrederikDocs. Confirm the ext4
   cache mount and active `cachefilesd`. Check the initializer and mount units
   for failures.
6. Verify normal-user and service access, downloads, and imports. Confirm real
   disk-cache reads after evicting only test data from client RAM. Check that a
   change through another client invalidates the cached SMB data. Then repeat
   the cutover on the other host.

Build-time checks do not verify live Synology permissions, service membership,
SMB lease behavior, or cache hits. Keep
activation and live verification pending until these checks pass on both hosts.
Do not drop global RAM caches on a live media server just to test FS-Cache.

## Resizing or discarding the cache

Change `services.nasMediaCache.sizeGiB` only during a cache maintenance window.
Stop consumers and all five cached automounts/mounts, stop `cachefilesd`, and
unmount `/var/cache/fscache` before replacing its disposable image. Stop the
initializer too, so its completed oneshot state cannot skip initialization.
Never remove or resize an image while its loop filesystem is mounted. Never
remove data under `/mnt/nas` when resetting the local cache.
