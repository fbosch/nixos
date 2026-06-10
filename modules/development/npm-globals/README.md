# npm-globals

Lockfile-driven global npm tooling for Home Manager.

The workflow here is lockfile-based, not pure Nix-built: Home Manager activation invokes `pnpm install --frozen-lockfile --prod` using `package.json`, `pnpm-lock.yaml`, and `pnpm-workspace.yaml` from this folder. It also makes it practical to track newer package releases while keeping changes reviewable for security auditing.

Commands:

- `pnpm-global-update`: refresh lockfile from pinned `package.json` versions, then install globals
- `pnpm-global-upgrade`: interactive upgrades, then install pinned globals
- `pnpm-global-install`: install directly from current lockfile

Home Manager activation also installs from the committed lockfile into `$HOME/.local/state/pnpm-globals/current` and exposes its `node_modules/.bin` on PATH. Activation is non-blocking: failed installs warn and can be retried with `home-manager switch` or `pnpm-global-install`.

Use `NPM_GLOBALS_DIR=/path/to/npm-globals` or pass the directory as the first argument when running commands from a non-standard checkout path.
