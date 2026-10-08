# Investigate Pi's nono integration on Linux

Status: ready for operator investigation. No Linux runtime checks in this plan have run. Full host evaluation previously timed out, and Linux enforcement remains unverified.

## Scope and safety

Validate the existing-profile migration in `modules/development/ai/nono.nix`, the Stow launcher, and Linux Podman workflows. Start on `rvn-pc`; repeat the runtime checks on each Linux development host before declaring fleet support.

This plan does not enable selective protection. Networking, writable CWD, writable Pi state, and launcher-added grants remain unchanged. See [the selective-protection plan](./2026-10-08-nono-selective-protection.md) for that separate work.

Run the commands yourself in an ordinary terminal outside Pi, nono, and containers. If an agent executes diagnostics, it must first ask permission, run `hostname`, and use local commands only when already on the target host. An agent must not run the privileged commands below.

The examples use Bash. Open `bash` first if your login shell is Fish. Keep diagnostic logs local and redact paths, connection details, and credentials before sharing them. Do not dump the full environment or credential files. Do not modify production startup files to test enforcement.

## 1. Identify the host and deployed revisions

Run:

```bash
hostname
uname -r
printf 'Inherited nono marker: %s\n' "${NONO_CAP_FILE:+present}"
git -C "$HOME/nixos" status --short
git -C "$HOME/nixos" rev-parse HEAD
git -C "$HOME/dotfiles" status --short
git -C "$HOME/dotfiles" rev-parse HEAD
readlink -f /run/current-system
```

Confirm this is the intended Linux host. If `NONO_CAP_FILE` is present, stop and open a fresh ordinary terminal. Its absence alone is not proof that a parent has no restrictions.

Record both revisions and any uncommitted changes. Confirm the Nix checkout contains `modules/development/ai/nono.nix` and the dotfiles checkout contains the updated `nonoProfilePath()` selection and Podman integration in `.pi/agent/lib/nono-launch.ts`.

## 2. Finish host evaluation before activation

For `rvn-pc`, run from the Nix checkout:

```bash
cd "$HOME/nixos"
nix eval --raw .#nixosConfigurations.rvn-pc.config.system.build.toplevel.drvPath
nix build --no-link .#nixosConfigurations.rvn-pc.config.system.build.toplevel
```

Substitute the intended configuration name on another host. These commands evaluate and build; they do not activate. Nix ignores untracked files in Git flakes, so verify that the module belongs to the reviewed source revision before interpreting an evaluation result.

If evaluation or the build fails, record the first actionable error and stop deployment. Do not update the lockfile or change unrelated modules to force this check through.

If the configuration is not yet deployed, review the build and activate it through your normal operator-controlled rebuild workflow. Activation is a separate approval gate, not an instruction for an agent to run it. Reboot only if the reviewed changes require a new kernel. Continue after activation with a fresh terminal.

## 3. Verify the installed profile and entry points

Run:

```bash
NONO=/run/current-system/sw/bin/nono
RAW_PI=/run/current-system/sw/bin/pi
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
WRAPPER="$AGENT_DIR/bin/pi"

test -x "$NONO"
test -x "$RAW_PI"
test -x "$WRAPPER"
test -r /etc/nono/pi.json
readlink -f /etc/nono/pi.json
"$NONO" --version
command -v bun
bun --version
type -a pi
"$NONO" run --help
"$NONO" profile --help
"$NONO" profile validate /etc/nono/pi.json
"$NONO" profile show /etc/nono/pi.json
"$NONO" profile groups user_caches_linux
"$NONO" profile groups linux_sysfs_read
```

Expected results:

- `/etc/nono/pi.json` resolves to the generated Nix store file, and validation succeeds.
- Linux cache and sysfs groups resolve on this host. Review inherited groups as well as the authored JSON, including any user profile that shadows `default`.
- The ordinary `pi` command selects the Stow wrapper. The absolute `RAW_PI` path remains available without the wrapper.
- Bun can load the launcher's installed dependencies. Do not install packages or regenerate lockfiles merely to run this investigation.

The raw profile contains a macOS Seatbelt semaphore rule. Nono applies it only on macOS; it does not grant Linux System V IPC permissions.

If a command differs in the installed nono version, inspect its `--help` before adapting it. Record the version. Current upstream documentation can describe newer behavior than the deployed package.

## 4. Check the running kernel and actual sandbox startup

Run:

```bash
"$NONO" setup --check-only
cat /sys/kernel/security/lsm
```

If reading the LSM list fails for lack of permission, run this yourself:

```bash
sudo cat /sys/kernel/security/lsm
```

Check for `landlock`. Kernel version alone is insufficient. `rvn-pc` selects a CachyOS kernel in `modules/hosts/rvn-pc/boot.nix`; inspect the running kernel rather than assuming the configured package is active.

Then run a fresh sandbox from a disposable CWD:

```bash
WORK=$(mktemp -d "$HOME/pi-nono-linux.XXXXXX")
printf 'Investigation directory: %s\n' "$WORK"
cd "$WORK"
"$NONO" run --dry-run -v --profile /etc/nono/pi.json --allow-cwd -- /run/current-system/sw/bin/true
"$NONO" run -vv --profile /etc/nono/pi.json --allow-cwd -- /run/current-system/sw/bin/true
```

Record the detected Landlock ABI, enforcement status, warnings, and exit status. A successful dry-run is not evidence that the kernel applied restrictions. The second command must start a real sandboxed child.

Interpret signal isolation separately:

| Running kernel capability | Meaning of this profile's `signal_mode = "isolated"` |
| --- | --- |
| Before Landlock ABI v6 | Nono 0.74.0 does not enforce signal scoping. |
| Landlock ABI v6, normally Linux 6.12 or newer | Nono 0.74.0 restricts signals to the same sandbox domain, not strictly to self. |

Do not change kernel parameters from a copied generic LSM list. If Landlock is absent, inspect `CONFIG_SECURITY_LANDLOCK`, the active LSM configuration, and boot parameters before proposing a reviewed kernel change. Preserve existing AppArmor and other LSM requirements.

## 5. Verify filesystem restrictions with disposable files

The fixture is under your home rather than `/tmp`, because inherited temporary-directory grants can otherwise allow the intended denied write. Check the resolved probe profile for any other grant covering the fixture's parent.

Use a narrow test profile to isolate Landlock behavior from the intentionally broad production grants. Keep the `WORK` variable from step 4:

```bash
mkdir -p "$WORK/allowed" "$WORK/outside"
printf 'unchanged\n' > "$WORK/outside/sentinel"
cat > "$WORK/probe.json" <<'JSON'
{
  "extends": "default",
  "meta": { "name": "linux-filesystem-probe", "description": "Disposable enforcement check" },
  "groups": { "include": ["nix_runtime"] },
  "security": { "signal_mode": "isolated", "capability_elevation": false },
  "network": { "block": false },
  "workdir": { "access": "readwrite" }
}
JSON
cd "$WORK/allowed"
SH=$(command -v sh)
"$NONO" run -v --profile "$WORK/probe.json" --allow-cwd -- "$SH" -c 'printf "allowed\n" > ./created'
"$NONO" run -v --profile "$WORK/probe.json" --allow-cwd -- "$SH" -c 'printf "changed\n" > "$1"' sh "$WORK/outside/sentinel"
printf 'Denied-write exit status: %s\n' "$?"
cat "$WORK/allowed/created"
cat "$WORK/outside/sentinel"
```

Run these in an interactive Bash session without `set -e`, because the denied command should fail. The first write must succeed. The second must fail with a permission denial, and the sentinel must still contain `unchanged`. A startup failure is not a successful denial test.

If the outside write succeeds, inspect inherited grants and canonical paths before blaming Landlock. Do not widen or rewrite the production profile during this test.

This proves only the tested basic filesystem restriction. It does not establish selective protection for the live dotfiles checkout. Landlock grants are additive; a read-only child grant cannot override a writable ancestor.

## 6. Exercise the actual Pi launcher

From the disposable directory, compare entry points:

```bash
cd "$WORK/allowed"
"$WRAPPER" --help
"$WRAPPER" --no-sandbox --help
"$RAW_PI" --help
```

The wrapped invocation must start through nono without initialization errors. The other two invocations intentionally bypass new nono confinement. `--no-sandbox` must remain the first argument. None can remove confinement inherited from a parent.

Next, launch ordinary `pi` and manually exercise the following with non-secret fixture data:

1. Create and resume a session.
2. Read a configured project reference and perform an ordinary edit in the disposable CWD.
3. Load the usual extensions and exercise FFF/LMDB searches and hashline state.
4. Use a previously approved direnv project. Do not approve an unknown `.envrc` for this test.
5. Start a nested agent and confirm it remains within inherited restrictions. The presence of `NONO_CAP_FILE` is not an enforcement test; perform a denied write to a disposable path outside its actual grants.

Record exact failed operations, paths, errors, and which invocation produced them. Existing writable reference and Stow-target grants can make a path unsuitable for a denial test. Do not test writes against production shell or launcher files.

## 7. Investigate Linux Podman separately

First establish the unsandboxed baseline from the ordinary terminal:

```bash
podman --version
podman info
podman ps
printf 'XDG_RUNTIME_DIR: %s\n' "${XDG_RUNTIME_DIR:-unset}"
systemctl --user status podman.socket --no-pager
```

The socket check applies when the host imports the Home Manager Podman module. It declares `%t/podman/podman.sock`. Local Podman CLI use and API-socket use are different workflows; an inactive socket does not by itself explain a local CLI failure.

Then run `podman info` and `podman ps` through Pi's command tool in the wrapped session. Compare them with the baseline. These checks can initialize runtime state, but do not pull images, create containers, or prune storage.

If the wrapped checks fail:

1. Determine whether the client uses native rootless storage, a local API socket, or a remote connection. Inspect connection configuration locally without publishing credential material.
2. Record the denied path or syscall. Distinguish filesystem access, socket access, user-namespace setup, and helper execution.
3. Check the installed nono version's socket controls before adding any grant. Do not assume current upstream AF_UNIX options exist in the deployed version.
4. Propose the smallest permission change only after identifying the failure. Do not broadly grant `~/.local/share/containers`, `/run/user`, `/run`, or private SSH keys.

The existing launcher grants Podman connection metadata and public `known_hosts` when the connection file exists. Its `XDG_RUNTIME_DIR` workaround applies only on Darwin. Neither establishes native Linux rootless Podman compatibility.

Treat a working Podman API connection as a security exception, not an isolated container-only permission. A runtime service outside nono can perform operations using that service's host privileges, including mounting host paths. Do not switch to socket-based execution as a workaround without reviewing that risk.

A container create/run test is a later operator-approved gate. Use an already-present image and disposable data, with no production mounts, no new exposed ports, and explicit cleanup of only the test container.

## 8. Investigate stale file grants if observed

Linux Landlock file-level grants bind to inodes. If another process atomically replaces a granted file, the new inode can become inaccessible to an existing sandbox. Restarting Pi rebuilds grants against the current file.

If Podman connection configuration or `known_hosts` becomes unreadable after an external update, compare a fresh Pi session with the existing session. Reproduce replacement only with a disposable fixture file. Do not edit real connection or SSH configuration to demonstrate this behavior, and do not replace a narrow file grant with broad directory access without review.

## Results and exit gates

Fill in this table after execution. Leave unavailable checks unverified.

| Check | Result and evidence |
| --- | --- |
| Host, kernel, Nix revision, dotfiles revision, dirty changes | Pending |
| Full host evaluation and build | Pending |
| Activation and installed `/etc/nono/pi.json` | Pending |
| Installed nono version and resolved Linux groups | Pending |
| Landlock ABI and real sandbox startup | Pending |
| Signal isolation limitations accepted | Pending |
| Disposable allowed write and denied outside write | Pending |
| Wrapped Pi, explicit bypass, and raw Pi | Pending |
| Session, references, extensions, LMDB, direnv, and nested agent workflows | Pending |
| Unsandboxed versus wrapped Podman | Pending |
| File-replacement issue, if observed | Pending or not applicable |

Accept the ownership migration on a host only after its profile selection, real sandbox startup, filesystem probe, and required workflows pass. Keep Podman unsupported on that host if its required workflow remains blocked. Do not label Linux selective protection complete from these results.

The full Pi typecheck also remains blocked by errors outside the migration. Runtime success does not resolve that separate validation gap. Keep the Stow profile fallback until every development host has the system profile and updated launcher; remove it before any selective-protection policy diverges.

Leave the temporary investigation directory in place until evidence review. Afterwards, remove only the printed `WORK` directory you created. Do not use wildcard cleanup or prune Podman storage.

## References

- [Existing migration and selective-protection plan](./2026-10-08-nono-selective-protection.md)
- [Nono Linux Landlock documentation](https://nono.sh/docs/cli/internals/landlock)
- [Nono 0.74.0 Linux enforcement source](https://docs.rs/nono/0.74.0/src/nono/sandbox/linux.rs.html)
- [Nono profile introspection](https://nono.sh/docs/cli/features/profile-introspection)
- [Nono CLI reference](https://nono.sh/docs/cli/usage/flags)

Check documentation against the version recorded in step 3. This plan was written on `rvn-mac`; no Linux commands above were executed during authoring.
