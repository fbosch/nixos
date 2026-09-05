# Forgejo NAS Migration

This runbook moves the existing Forgejo instance from `rvn-srv` to storage local to the NAS. It restores the verified archive at the `backup/forgejo/forgejo-dump.tar.zst` path in the NAS `backup` shared folder.

The archive was created by Forgejo `15.0.7`; restore it with `codeberg.org/forgejo/forgejo:15.0.7` before considering an upgrade. Forgejo supports direct upgrades between major releases only with the manual checks in its [upgrade guide](https://forgejo.org/docs/v15.0/admin/upgrade/).

## Safety boundary

- Live state must be on a local NAS volume. Do not bind-mount a CIFS, NFS, or other remote share into the container.
- Do not run the installer or create a new Forgejo database. The archive contains the existing SQLite database, repositories, LFS objects, and application configuration.
- Treat the extracted `app.ini` as secret material. It contains the keys needed to decrypt existing data and must not be copied to chat, tickets, shell history, or logs.
- Keep `rvn-srv` Forgejo stopped throughout the migration. It must never become a second writer.
- Do not delete the old `rvn-srv` state until every validation gate below has passed and the NAS has completed a new backup.

## Prerequisites

1. Verify the NAS identity by an independent channel before accepting its new SSH host key. Do not bypass host-key checking.
2. Confirm that Synology Container Manager is available and that the NAS volume selected for Forgejo has at least the archive size plus the restored data size and backup headroom available.
3. Choose a local NAS directory for persistent state, referred to below as `$FORGEJO_STATE_DIR`. It must be on the NAS filesystem, not in the mounted `backup` share. Keep the archive in its original `backup` location.
4. Choose a dedicated NAS user/group ID, `$FORGEJO_UID:$FORGEJO_GID`, that owns `$FORGEJO_STATE_DIR`. The official image requires the bind mount to be owned by the `USER_UID` and `USER_GID` values.
5. Choose the private container listener port, `$FORGEJO_HTTP_PORT`, and confirm it does not collide with an existing NAS service. The published port should bind only to `127.0.0.1`; Synology Reverse Proxy provides HTTPS access.
6. Ensure the NAS terminal, or a disposable tool container, provides `zstd`, `tar`, `rsync`, and Git. The commands below must run only against the copied archive and the new empty state directory.

## Inspect the archive

Create a staging directory on the local NAS volume. Do not extract directly into the production state directory.

```sh
archive='<NAS backup shared folder>/forgejo/forgejo-dump.tar.zst'
staging='<local NAS volume>/forgejo-restore-staging'

zstd -q -t "$archive"
mkdir -p "$staging"
zstd -dc -- "$archive" | tar -C "$staging" -xf -
find "$staging" -maxdepth 2 -mindepth 1 -printf '%P\n' | sort | sed -n '1,160p'
```

The expected top-level members are `app.ini`, `forgejo-db.sql`, `data/`, `repos/`, and, when present, `custom/`. The restore uses the SQLite database in `data/forgejo.db`; `forgejo-db.sql` is retained as recovery evidence and is not imported.

Stop here if the archive fails its integrity test, lacks `data/forgejo.db`, or lacks `repos/`. Preserve the archive and investigate before making any change to the source host.

## Prepare the Container Manager project

Create the project manually in Synology Container Manager. The following Compose-compatible definition records the required container contract; substitute the chosen local path, IDs, and port before creating the project.

```yaml
services:
  forgejo:
    container_name: forgejo
    image: codeberg.org/forgejo/forgejo:15.0.7
    restart: unless-stopped
    environment:
      USER_UID: "${FORGEJO_UID}"
      USER_GID: "${FORGEJO_GID}"
    ports:
      - "127.0.0.1:${FORGEJO_HTTP_PORT}:3000"
    volumes:
      - "${FORGEJO_STATE_DIR}:/data"
      - "/etc/localtime:/etc/localtime:ro"
```

Do not expose the image's SSH port. The old instance had SSH disabled, so HTTP(S) is the only supported clone transport for this move.

Create `$FORGEJO_STATE_DIR` and make it owned by `$FORGEJO_UID:$FORGEJO_GID`. Leave the project stopped until the archive has been restored.

## Restore the state

Copy each archive component to the directory the container sees as `/data`:

```sh
state="$FORGEJO_STATE_DIR"
install -d -m 0750 "$state/gitea/conf" "$state/gitea/custom"
rsync -a -- "$staging/data/" "$state/"
rsync -a -- "$staging/repos/" "$state/forgejo-repositories/"
if [ -d "$staging/custom" ]; then
  rsync -a -- "$staging/custom/" "$state/gitea/custom/"
fi
install -m 0600 -- "$staging/app.ini" "$state/gitea/conf/app.ini"
chown -R "$FORGEJO_UID:$FORGEJO_GID" "$state"
```

Edit `$state/gitea/conf/app.ini` without printing its contents. Preserve all existing `[security]` values, including `SECRET_KEY` and `INTERNAL_TOKEN`, and the existing `LFS_JWT_SECRET` if present. Those values are required to retain access to encrypted data and LFS authentication.

Update only the NAS-specific locations and listener settings:

```ini
[server]
APP_DATA_PATH = /data
HTTP_ADDR = 0.0.0.0
HTTP_PORT = 3000
ROOT_URL = https://forgejo.corvus-corax.synology.me/
DISABLE_SSH = true

[database]
DB_TYPE = sqlite3
PATH = /data/forgejo.db

[repository]
ROOT = /data/forgejo-repositories

[lfs]
PATH = /data/lfs

[service]
DISABLE_REGISTRATION = true
```

Keep `INSTALL_LOCK = true` and `COOKIE_SECURE = true`. If Synology Reverse Proxy reaches the container from an address other than loopback, add only its actual bridge address or CIDR to `[security] REVERSE_PROXY_TRUSTED_PROXIES`; do not use `*`. Restart the project after editing the configuration.

## Publish the service

In Synology Reverse Proxy, create or update the HTTPS rule for `forgejo.corvus-corax.synology.me` to the local `127.0.0.1:$FORGEJO_HTTP_PORT` listener. Preserve TLS termination at the NAS and configure the proxy to forward the standard `Host` and `X-Forwarded-*` headers.

Do not add WAN port forwarding. This service is intended for LAN and Tailscale access. Restrict NAS firewall rules accordingly.

## Validate before cutover

Run these checks before changing DNS, deleting state, or allowing normal use:

1. Confirm Container Manager reports the container running and no installer page is served. An installer page means the old configuration or database is not being read; stop the container and correct the restore.
2. From the container, run `forgejo --config /data/gitea/conf/app.ini doctor check --all --log-file -`. Resolve every reported error before proceeding.
3. Log in through the reverse-proxied HTTPS URL. Check the administrator account, repository inventory, and at least one issue or release if present.
4. Clone a representative public or private repository through the NAS URL, then run `git -C <clone> fsck --full`.
5. Compare the heads and tags of the clone endpoint against the expected archive recovery point. Investigate differences rather than assuming the current GitHub state is the archive state.
6. If `data/lfs/` exists, clone a repository with LFS objects, fetch the LFS content, and run `git lfs fsck`.
7. Create and verify a new NAS-native backup or snapshot of `$FORGEJO_STATE_DIR`. Keep the imported archive as a separate recovery input until this backup is known to be usable.

Record the archive path, integrity result, restore date, container image digest, validation repositories, and any data classes not verified.

## Retire `rvn-srv`

Only after the NAS validation gates pass:

1. Confirm the source remains inactive and its backup timers cannot run:

   ```sh
   ssh srv 'for unit in forgejo.service forgejo-backup.timer forgejo-backup-export.timer; do printf "%s: " "$unit"; systemctl is-active "$unit" || true; done'
   ```

   Each command must report `inactive` or `unknown`; any active unit is a cutover blocker.

2. Activate the repository change that removes the Forgejo NixOS aspect from `rvn-srv`. It also removes its health checks, port `3000/tcp`, backup units, and firewall rule.
3. After the new configuration is active and the NAS backup is verified, remove the source-only data from `rvn-srv` as an explicit administrator action:

   ```sh
   sudo rm -rf /var/lib/forgejo /var/backup/forgejo
   ```

4. Remove the now-unused `forgejo-admin-password` entry with interactive SOPS editing of `secrets/containers.yaml`, then re-encrypt it. Never delete encrypted YAML lines manually because that invalidates its authenticated metadata.

Keep the NAS archive and snapshots according to the NAS retention policy. A failure at any point before step 3 is a rollback: stop the NAS container, preserve its state for diagnosis, and leave the old `rvn-srv` data untouched.

## References

- [Forgejo 15.0 container installation](https://forgejo.org/docs/v15.0/admin/installation/docker/)
- [Forgejo 15.0 configuration reference](https://forgejo.org/docs/v15.0/admin/config-cheat-sheet/)
- [Forgejo 15.0 upgrade and verification guidance](https://forgejo.org/docs/v15.0/admin/upgrade/)
