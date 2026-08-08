# Home Manager Ownership Boundaries

## Goal

Establish explicit ownership boundaries without replacing GNU Stow:

- NixOS and nix-darwin own machine state and generally available packages.
- Home Manager owns user state, user sessions, generated user files, and user services.
- GNU Stow owns portable, hand-maintained dotfiles that remain editable without a rebuild.

Keep the existing feature-oriented dendritic layout. Related NixOS, Darwin, and Home Manager declarations stay colocated.

## Decisions Required Before Implementation

1. Select the Git credential helper strategy: cross-platform GCM, or Linux Secret Service plus macOS Keychain.
2. Select one `rvn-srv` SSH-agent strategy: Home Manager `ssh-agent`, or GPG agent with SSH support.
3. Confirm whether either Mac manages Remote Login; machine login keys must not come from the generic Home Manager SSH client module.
4. Decide whether Darwin `DOCKER_HOST` is Fish-only or must reach GUI and LaunchAgent clients.
5. Define the minimum supported rollback generation for `.npmrc` and `.wakatime.cfg` ownership migration.
6. Confirm exact Surge download roots for every host.
7. Decide whether `rvn-srv` should retain the full shared development tool set after packages become system-owned.
8. Confirm that Stow intentionally does not configure GTK on a clean standalone checkout.

## Slice 1: Record the Contract

**Outcome:** Maintainers can determine an owner from a path or responsibility before changing implementation.

**Changes**

- Replace the absolute rules in `docs/agents/dotfiles-policy.md` with path- and responsibility-based ownership rules.
- Add an ADR documenting the NixOS/nix-darwin, Home Manager, and Stow boundary.
- Add an exact-path ownership manifest covering Fish generated state, Git includes, GTK, SSH authorization, MIME, `.npmrc`, `.wakatime.cfg`, terminals, editors, and desktop entries.
- Record the cross-repository handoff rule: Nix and dotfiles repositories may update independently, so every move needs an old/new compatibility window.

**Acceptance criteria**

- The policy distinguishes package installation from program configuration.
- It explicitly forbids Home Manager child files below Stow-linked directories.
- It states that machine login authorization is system-owned and SSH client configuration is Home Manager-owned.
- It preserves Stow as independently usable and bans automated `stow --adopt`.

**Risk:** None. Documentation only.

## Slice 2: Remove Security Ownership Ambiguity

**Outcome:** Each login authorization source and SSH-agent implementation has one owner.

**Changes**

- In `modules/shell/ssh.nix`, stop declaring `home.file.".ssh/authorized_keys"` for NixOS hosts after preserving the current key union in `users.users.<name>.openssh.authorizedKeys`.
- Keep Home Manager ownership of SSH client host blocks, private-key-derived public key, and the selected user-session agent.
- In `modules/hosts/rvn-srv/platform/system.nix` and relevant Home Manager modules, retain only the selected SSH-agent strategy.
- Add an assertion preventing GPG SSH support and `services.ssh-agent` from both being active on the same host.
- Decide and document the machine-level Darwin Remote Login owner before applying any Mac authorized-key configuration.

**Acceptance criteria**

- NixOS evaluation has exactly one configured source for SSH login authorized keys.
- `rvn-srv` has exactly one SSH agent socket strategy.
- SSH client connections, generated public keys, and current authorized keys continue to work.

**Risk:** High. This changes an authorization boundary; validate keys before removing either current source.

## Slice 3: Repair Existing User-Service and Session Defects

**Outcome:** Existing user-state ownership remains intact, but known lifecycle defects are removed before larger migrations.

**Changes**

- Change `modules/shell/bat.nix` to depend on the actual `dotfiles` activation node instead of retired `stowDotFiles`.
- Bound Bat cache input traversal; do not recursively follow arbitrary directory symlinks from Stow-managed themes or syntaxes.
- In `modules/virtualization/podman.nix`, remove the hardcoded Darwin `DOCKER_HOST` behavior or derive it from `podman machine inspect` consistently with the Fish profile.
- If session-wide Docker access is required, publish the discovered socket through the LaunchAgent; otherwise leave runtime discovery in Fish only.
- Add launchd log retention or use unified logging for Podman, Headroom, and Pxpipe.
- In `modules/applications/surge.nix`, make successful `exitWhenDone` completion compatible with systemd restart behavior.

**Acceptance criteria**

- Bat themes are stowed before its cache is built.
- A malicious or accidental large directory symlink cannot make Home Manager recursively hash an arbitrary filesystem tree.
- Darwin interactive and non-Fish Podman clients have one documented socket behavior.
- A completed Surge queue does not restart when `exitWhenDone` is enabled.

**Risk:** Medium. Validate user services on `rvn-pc` and Darwin separately.

## Slice 4: Publish Dotfiles Compatibility

**Outcome:** Existing mutable dotfiles checkouts can safely coexist with the future Home Manager ownership model.

**Changes**

- Update `dotfiles/.config/fish/config.fish` to prefer a generated file outside `.config/fish`, with a temporary fallback to legacy `private.fish`.
- Keep the fallback for one documented compatibility window.
- Add an optional generated Git include to Stow's `.gitconfig`; retain portable name, email, signing key, aliases, diff behavior, and GitHub username in Stow.
- Keep GTK roots excluded in `.stow-local-ignore`.
- Exclude `.direnv` runtime state from Stow.

**Acceptance criteria**

- Old Home Manager output remains usable with new dotfiles.
- New Home Manager output can be consumed by updated dotfiles without writing into the Stow checkout.
- A Stow-only Git configuration retains portable identity and GitHub username.
- A clean Stow run does not deploy `.direnv` state or GTK roots.

**Risk:** Medium. Deploy this slice to all managed dotfiles checkouts before changing Home Manager writers.

## Slice 5: Establish Non-Destructive Secret-File Compatibility

**Outcome:** The current system owners of `.npmrc` and `.wakatime.cfg` no longer overwrite arbitrary user files during a later handoff or rollback.

**Changes**

- In `modules/files/npmrc.nix` and `modules/files/wakatime.nix`, replace forceful NixOS tmpfiles and Darwin `ln -sf` behavior with guarded handling.
- Treat only the exact known rendered-SOPS symlink target as migratable.
- Refuse regular files, directories, broken or unknown symlinks, and symlink ancestors outside the known contract.
- Define the generation containing these safeguards as the earliest supported rollback point.

**Acceptance criteria**

- Existing known system SOPS links remain functional.
- A regular file, directory, or unknown symlink is preserved and produces an actionable error.
- No secret value or template content appears in activation output.

**Risk:** High. This must ship before Home Manager takes ownership of either path.

## Slice 6: Add System Package Destinations

**Outcome:** Packages are available from the machine profile before Home Manager copies are removed.

**Changes**

- Inventory each package by active host rather than moving entire aggregate aspects mechanically.
- Add NixOS and/or Darwin owners only where an active host consumes the package entry.
- Move pure development packages from Home Manager to system contexts:
  - languages, language servers, Node tooling, Python tooling, AI tools, and general development tools;
  - preserve `npm-globals` in Home Manager.
- Move pure shell and desktop packages to the relevant system contexts:
  - monitoring, shell utilities, Fish tooling, terminals, GNOME/Hyprland tools, and package-only desktop applications.
- Move only actual font packages to system font declarations; keep Home Manager fontconfig, user font data, and font-cache activation.
- Move SOPS, age, Bitwarden CLI, and ClamAV command packages to system contexts while retaining Home Manager GPG/user-secret configuration.
- Add Darwin package destinations before removing shared HM package entries used by `rvn-mac` or `kmd-mac`.
- Do not add Darwin destinations for PC/VM-only desktop packages.

**Acceptance criteria**

- Each active host retains every intentionally supported command before HM removal.
- System package destinations are present one generation before HM package deletion.
- `rvn-srv` package scope is explicitly chosen rather than inherited accidentally.
- Linux package duplicates are visible in an inventory before deletion.

**Risk:** Medium. The main risk is a missing command on Darwin or unintended expansion of the server closure.

## Slice 7: Cut Over Pure Package Ownership

**Outcome:** Home Manager stops being a general package installer where it has no user-state responsibility.

**Changes**

- Remove pure `home.packages` entries only after Slice 6 is deployed and verified.
- Retain Home Manager packages that directly back user services, activations, generated commands, or material `programs.*` configuration.
- Remove exact duplicates first: Linux Podman tools, `uv`, Luacheck, `just`, `p7zip`, `xdg-utils`, FreeRDP, and duplicate `zoxide`.
- Consolidate VLC and Helium under their NixOS Firejail/system package owners while retaining Home Manager user setup where required.
- Move application package lists out of HM while retaining Flatpak application selection, overrides, MIME, desktop entries, and application preferences in HM.

**Acceptance criteria**

- `home.packages` contains only user-lifecycle dependencies or intentionally user-scoped packages.
- `type -a` and application launch paths resolve to the expected system owner.
- HM-managed program configuration, Flatpak state, desktop entries, and user services remain unchanged.

**Risk:** Medium. Apply per feature and validate command availability before removing the next list.

## Slice 8: Complete the Stow/Home Manager Path Boundary

**Outcome:** Home Manager and Stow no longer own the same path or parent directory.

**Changes**

- Move generated Fish state to a Home Manager-only path outside `.config/fish`.
- Publish generated Fish state atomically: create a mode-`0600` temporary file in its final directory and rename it into place only after a successful write.
- Walk all ancestors with `lstat` before migration; do not consider a leaf safe when a parent is a Stow symlink.
- Remove legacy `private.fish` only if it is the known generated file or known Stow-through path; preserve unknown user files.
- Make Home Manager the complete owner of GTK on managed Linux desktops:
  - reproduce required GTK settings, CSS, Nemo bookmarks, and required assets from immutable Nix sources;
  - do not recreate existing absolute `/home/fbb/.local/share/...` GTK symlinks;
  - remove stale GTK root links only when they resolve exactly to the known dotfiles paths;
  - restore recognized links if the cutover fails.
- Remove dormant GTK files from dotfiles after verified parity and the rollback window.

**Acceptance criteria**

- HM creates no child below a Stow-linked directory.
- Fish starts with host variables and `with-secret` after all supported Nix/dotfiles version combinations.
- GTK is complete on a clean Linux home without Stow GTK ownership.
- GTK activation refuses unknown real directories or symlink targets.

**Risk:** High. This is a two-repository filesystem migration and needs canary rollout on `rvn-pc` first.

## Slice 9: Clarify Git, Podman, and Surge Mixed Features

**Outcome:** Mixed features have a small, explicit system/user contract with no cross-class configuration inspection.

**Changes**

- Git:
  - generate only platform helper configuration and host-specific maintenance repositories through the Home Manager include;
  - retain portable settings in Stow;
  - install and verify the selected credential helper before enabling it;
  - ensure only one effective helper is configured.
- Podman:
  - retain NixOS runtime, pruning, system socket, and group membership;
  - retain HM Linux rootless socket and Darwin LaunchAgent;
  - add/import a Darwin system package aspect before removing Darwin HM Podman packages;
  - do not keep a second Podman closure in HM merely because the LaunchAgent references a store path.
- Surge:
  - define the package and allowed download roots in the NixOS aspect;
  - have the HM service use that system-owned package contract;
  - remove NixOS reads from `home-manager.users`;
  - attach AppArmor to the same package and restrict it to exact config, state, runtime, and output paths;
  - import the NixOS Surge aspect explicitly on `rvn-pc`.

**Acceptance criteria**

- `git config --show-origin --get-all credential.helper` reports exactly one valid helper per host.
- Darwin Podman remains available in interactive and documented non-Fish contexts after HM packages are removed.
- Surge is confined after normal service restart and supported system/HM rollback combinations.
- Surge cannot write unrelated shell, Git, browser, SSH, or SOPS paths.

**Risk:** High for Surge; medium for Git and Podman.

## Slice 10: Transfer User Secret Files to Home Manager

**Outcome:** `.npmrc` and `.wakatime.cfg` have one user-level owner with user-scoped secret material.

**Changes**

- Add npm and Wakapi secret declarations, templates, permissions, and target paths to Home Manager SOPS configuration.
- Use user-only permissions for source secrets and rendered files.
- In one integrated generation, disable the guarded system writers and enable HM ownership.
- Retain explicit migration checks from Slice 5 and reject rollback before the compatibility floor.
- Remove obsolete NixOS/Darwin host imports only after all consumers use the HM implementation.

**Acceptance criteria**

- Existing recognized system links migrate without exposing secret values.
- HM owns both the secret lifecycle and final `$HOME` path.
- Regular files and unknown links remain untouched.
- Supported rollback remains non-destructive.

**Risk:** High. Canary on `rvn-pc`, then `rvn-mac`, then `rvn-srv`; `kmd-mac` does not currently import HM secrets.

## Slice 11: Encode the Boundary

**Outcome:** Future changes cannot easily reintroduce known ownership errors.

**Changes**

- Extend Nix unit checks for:
  - no automated `--adopt`;
  - Bat dependency on `dotfiles`;
  - no HM `authorized_keys` on NixOS hosts;
  - one SSH-agent strategy on `rvn-srv`;
  - generated Fish state outside Stow trees;
  - GTK exact-path single ownership;
  - safe secret-file migration semantics;
  - Linux HM/system duplicate package assertions;
  - active-host package destination coverage;
  - Git helper existence and single effective configuration;
  - Surge package/policy consistency and output-root allowlists.
- Evaluate all active hosts in CI: `rvn-pc`, `rvn-mac`, `kmd-mac`, `rvn-srv`, and `rvn-vm`.
- Evaluate inactive aspects in isolation: minimal/server presets, Waydroid, and Pxpipe.

**Acceptance criteria**

- Cheap static boundary checks run on every relevant change.
- Package ownership changes trigger active-host evaluations.
- Representative Linux and Darwin closures are built when package ownership changes, rather than on unrelated edits.

**Risk:** Low. Keep checks targeted; do not turn every ownership edit into a full multi-platform build by default.

## Rollout Order

1. Slice 1: document the contract.
2. Slice 2: remove SSH authorization and agent ambiguity.
3. Slice 3: repair known service/session defects.
4. Slice 4: publish dotfiles compatibility.
5. Slice 5: establish the secret-file rollback floor.
6. Slice 6: add system package destinations.
7. Slice 7: remove pure HM package ownership.
8. Slice 8: perform Fish and GTK filesystem cutovers.
9. Slice 9: finish Git, Podman, and Surge mixed-feature contracts.
10. Slice 10: move `.npmrc` and `.wakatime.cfg` to HM.
11. Slice 11: encode checks and remove compatibility paths after the defined window.

Each slice is independently reviewable. Do not combine a new ownership writer with deletion of an old writer until the preceding compatibility slice is active and validated.
