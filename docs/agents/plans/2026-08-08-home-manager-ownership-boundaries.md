# Home Manager Ownership Boundaries

## Goal

Establish explicit ownership boundaries without replacing GNU Stow:

- NixOS and nix-darwin own machine state and generally available packages.
- Home Manager owns user state, user sessions, generated user files, and user services.
- GNU Stow owns portable, hand-maintained dotfiles that remain editable without a rebuild.

Keep the existing feature-oriented dendritic layout. Related NixOS, Darwin, and Home Manager declarations stay colocated.

## Decisions Required Before Implementation

1. Git uses Linux Secret Service and macOS Keychain credential helpers.
2. `rvn-srv` uses GPG agent SSH support; Home Manager `ssh-agent` remains the default on other hosts.
3. `rvn-mac` manages Remote Login and machine login keys; `kmd-mac` does not.
4. Darwin `DOCKER_HOST` is session-wide for GUI and LaunchAgent clients.
5. Surge download roots are defined per host by `services.surge.outputDir`.
6. `rvn-srv` retains the full shared development tool set after packages become system-owned.
7. Stow intentionally does not configure GTK on a clean standalone checkout.

## Slice 1: Record the Contract

**Outcome:** Maintainers can determine an owner from a path or responsibility before changing implementation.

**Changes**

- Replace the absolute rules in `docs/agents/dotfiles-policy.md` with path- and responsibility-based ownership rules.
- Add an ADR documenting the NixOS/nix-darwin, Home Manager, and Stow boundary.
- Add an exact-path ownership manifest covering Fish generated state, Git includes, GTK, SSH authorization, MIME, terminals, editors, and desktop entries.
- Record the cross-repository handoff rule: Nix and dotfiles repositories may update independently, so every move needs an old/new compatibility window.

**Acceptance criteria**

- The policy distinguishes package installation from program configuration.
- It documents the supported ignored generated-file handoff for `~/.config/fish/private.fish` and otherwise avoids Home Manager child files below Stow-linked directories.
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

- Add an optional generated Git include to Stow's `.gitconfig`; retain portable name, email, signing key, aliases, diff behavior, and GitHub username in Stow.
- Keep GTK roots excluded in `.stow-local-ignore`.
- Exclude `.direnv` runtime state from Stow.

**Acceptance criteria**

- A Stow-only Git configuration retains portable identity and GitHub username.
- A clean Stow run does not deploy `.direnv` state or GTK roots.

**Risk:** Medium. Deploy this slice to all managed dotfiles checkouts before changing Home Manager writers.

## Slice 5: Add System Package Destinations

**Outcome:** Packages are available from the machine profile before Home Manager copies are removed.

**Status:** Implemented with single-source package sets consumed by both system and Home Manager modules during the compatibility window. Active Darwin hosts now import the system `shell` and `virtualization/podman` aspects, and `rvn-srv` retains the full development set.

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

## Slice 6: Cut Over Pure Package Ownership

**Outcome:** Home Manager stops being a general package installer where it has no user-state responsibility.

**Changes**

- Remove pure `home.packages` entries only after Slice 5 is deployed and verified.
- Retain Home Manager packages that directly back user services, activations, generated commands, or material `programs.*` configuration.
- Remove exact duplicates first: Linux Podman tools, `uv`, Luacheck, `just`, `p7zip`, `xdg-utils`, FreeRDP, and duplicate `zoxide`.
- Consolidate VLC and Helium under their NixOS Firejail/system package owners while retaining Home Manager user setup where required.
- Move application package lists out of HM while retaining Flatpak application selection, overrides, MIME, desktop entries, and application preferences in HM.

**Acceptance criteria**

- `home.packages` contains only user-lifecycle dependencies or intentionally user-scoped packages.
- `type -a` and application launch paths resolve to the expected system owner.
- HM-managed program configuration, Flatpak state, desktop entries, and user services remain unchanged.

**Risk:** Medium. Apply per feature and validate command availability before removing the next list.

## Slice 7: Complete the Stow/Home Manager Path Boundary

**Outcome:** Stow and Home Manager have documented filesystem handoffs, and GTK has one owner on managed Linux desktops.

**Changes**

- Retain `~/.config/fish/private.fish` as the documented ignored generated-file handoff: Stow owns `config.fish`; Home Manager owns the generated leaf.
- Make Home Manager the complete owner of GTK on managed Linux desktops:
  - reproduce required GTK settings, CSS, Nemo bookmarks, and required assets from immutable Nix sources;
  - do not recreate existing absolute `/home/fbb/.local/share/...` GTK symlinks;
  - verify stale GTK root links resolve exactly to known dotfiles paths before removing them as a one-time migration step;
  - do not add permanent activation cleanup for this completed refactor.
- Remove dormant GTK files from dotfiles after verified parity and the rollback window.

**Acceptance criteria**

- Fish starts with host variables and `with-secret` through the documented generated-file handoff.
- GTK is complete on a clean Linux home without Stow GTK ownership.
- The one-time GTK cutover does not remove unknown real directories or symlink targets.

**Risk:** High. This is a two-repository filesystem migration and needs canary rollout on `rvn-pc` first.

## Slice 8: Clarify Git, Podman, and Surge Mixed Features

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

## Slice 9: Encode the Boundary

**Outcome:** Future changes cannot easily reintroduce known ownership errors.

**Changes**

- Extend Nix unit checks for:
  - no automated `--adopt`;
  - Bat dependency on `dotfiles`;
  - no HM `authorized_keys` on NixOS hosts;
  - one SSH-agent strategy on `rvn-srv`;
  - GTK exact-path single ownership;
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
5. Slice 5: add system package destinations.
6. Slice 6: remove pure HM package ownership.
7. Slice 7: complete the GTK filesystem cutover.
8. Slice 8: finish Git, Podman, and Surge mixed-feature contracts.
9. Slice 9: encode checks and remove compatibility paths after the defined window.

Each slice is independently reviewable. Do not combine a new ownership writer with deletion of an old writer until the preceding compatibility slice is active and validated.
