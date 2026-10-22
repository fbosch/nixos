# Plex next-episode prefetch

The `services/plex` aspect includes Plex and its prefetch helper. Both
`default.nix` and `prefetch.nix` contribute to that aspect under
`modules/services/plex/`. Importing Plex also includes prefetch, which requires
FS-Cache and the approved NAS video mount.

The helper reads at most the first 256 MiB of the next chronological episode,
at up to 10 MiB/s, with one reader. It uses ordinary buffered reads through
`/mnt/nas/video`, which populate RAM and FS-Cache. It does not write media,
change NAS permissions, or manipulate the cache image.

## Playback behavior

Play, resume, and shared-user playback-start webhooks can schedule work.
A watched event, normally sent near 90% playback, can refresh the next
episode's prefix before autoplay. Successful reads have a five-minute
cooldown, and concurrent viewers of the same file share one read.

The helper verifies the source episode and player against Plex's current
sessions before selecting a successor and again before reading queued work.
It ignores movies and specials. Selection follows season and episode numbers,
not shuffled play queues. When possible, it selects a version with the same
resolution as the currently playing version.

Pause and stop events cancel work when no other viewer needs that prefix.
Plex's owner webhook provides shared-user start events, but shared-user
pause/stop coverage depends on the webhook events available for that account.
Each job remains limited to 256 MiB. An in-flight read on a stalled hard NFS
mount may delay cancellation until the kernel returns.

Priming cannot guarantee a later cache hit. The 10 GiB cache is shared with
other approved NAS shares, and cache pressure can evict prefetched data.

## Credentials and request boundaries

Systemd passes Plex's existing `Preferences.xml` through a private runtime
credential. The helper extracts the owner token in memory and uses it only
in headers to the local Plex API on `127.0.0.1`. It does not follow redirects.

Plex does not sign native webhook payloads. The receiver instead requires a
secret capability URL derived from the owner token and server identity,
binds only to `127.0.0.1:32403`, and verifies playback against the local server.
The URL is a secret. Do not put it in the repository, logs, or screenshots.

The reader has a separate system user, the existing `nas-media` group, and
read-only media access. It accepts paths from authenticated Plex metadata,
not callback-supplied filenames. Traversal, symlinks, and non-regular files
are rejected. Pending viewers and the recent-completion cache are bounded.

## Activation and webhook setup

1. Activate from the current working tree on `rvn-pc`, targeting only
   `rvn-srv`, when ready. New module files must be tracked by Git so Nix
   includes them. A commit is not required:

   ```sh
   nixos-rebuild switch --flake .#rvn-srv --target-host rvn-srv --elevate sudo --ask-elevate-password
   ```

2. On `rvn-srv`, retrieve the private URL:

   ```sh
   sudo cat /run/plex-prefetch/webhook-url
   ```

3. In Plex Web, open the server owner's account settings, then Webhooks.
   Add that URL without removing existing webhooks. The owner needs an active
   [Plex Pass subscription](https://support.plex.tv/articles/115002267687-webhooks/).

4. Play a normal TV episode whose successor is under `/mnt/nas/video`.
   Live verification should confirm webhook delivery, service-UID read access,
   bounded bytes and rate, FS-Cache activity, and startup behavior on the
   receiving device. Fixture tests do not establish those runtime properties.

Restarting Plex also restarts the helper and reloads its credentials.
If the owner token changes, retrieve the new URL and update the Plex webhook.
Prefetch follows the Plex aspect and service lifecycle. Ordinary cache
eviction handles previously read data.

## Local checks

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s modules/services/plex/__tests__ -v
nix build .#checks.x86_64-linux.plex-prefetch --no-link
```

These checks use local fixtures. They do not contact the NAS, authenticate to
the production Plex server, or register a webhook.
