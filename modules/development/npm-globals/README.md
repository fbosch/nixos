# npm-globals

Lockfile-driven global npm tooling for Home Manager.

The workflow here is lockfile-based, not pure Nix-built: Home Manager activation invokes `pnpm` using `package.json` and `pnpm-lock.yaml` from this folder. It also makes it practical to track newer package releases while keeping changes reviewable for security auditing.

Commands:

- `pnpm-global-update`: refresh lockfile, then install pinned globals
- `pnpm-global-upgrade`: interactive upgrades, then install pinned globals
- `pnpm-global-install`: install directly from current lockfile
