# Nono selective protection for Pi

Status: the existing-profile ownership migration is implemented in the worktree. Full host verification and operator activation are pending. Selective protection remains deferred and unverified.

## Goal and agreed scope

Add a Nix-owned nono integration that prevents sandboxed Pi processes from changing selected files used by future unsandboxed launches. Keep the rest of the live dotfiles checkout editable.

- Keep protected hand-maintained files Stow-managed and editable by the user outside nono. Do not relocate them into the Nix store as the protection mechanism.
- Protect the launcher, its pre-sandbox dependencies, policy and grant inputs, and selected shell startup files against both modification and replacement.
- Keep ordinary project edits, required Pi state, extension caches, and nested agents working.
- Support macOS and Linux only after each platform passes its own enforcement tests. Do not silently run without the promised restrictions.
- Leave network access and unrelated live configuration outside this change. Selective protection is not a claim that all persistence or data-exfiltration routes are closed.

The user selected selective protection instead of a read-only live dotfiles checkout. Initial authorization covered saving this plan. Follow-up approval covered migrating the existing configuration into Nix with permissions unchanged and a temporary old-host fallback.

## Current integration and evidence

Paths beginning with `.pi/`, `.config/`, or `.shinit` below are relative to `~/dotfiles`; other repository paths are relative to `~/nixos`.

| Source | Current responsibility |
| --- | --- |
| `modules/development/ai/nono.nix` | Installs `pkgs.nono` and generates `/etc/nono/pi.json` for NixOS and Darwin development configurations. |
| `modules/development/ai/pi/default.nix` | Packages patched Pi and secures the user agent directory during Home Manager activation. |
| `.pi/agent/bin/pi` | Runs the TypeScript launcher through Bun before nono applies confinement. |
| `.pi/agent/lib/nono-launch.ts` | Resolves references and Stow targets, grants writable directories, and chooses sandboxed or direct Pi execution. |
| `.pi/agent/lib/nono/pi.json` | Retains the existing profile as a temporary fallback for hosts without `/etc/nono/pi.json`. |
| `.config/fish/config.fish`, `.shinit` | Configure host shells and put the Pi wrapper on PATH. |

The earlier read-only review on `rvn-mac`, using nono `0.74.0`, found that the active sandbox permitted writes to the wrapper, launcher, profile, Fish configuration, and `.shinit`. Corrected macOS kernel permission queries confirmed those permissions; `nono why --self` corroborated the launcher and Fish grants. No mutation or persistence payload was executed. Linux enforcement was not tested.

The launcher also treats any nonempty `NONO_CAP_FILE` as proof that it is already sandboxed. This can bypass sandbox creation in a future unsandboxed invocation, but changing the marker inside a confined process does not remove inherited restrictions.

Re-read the integration before changing permissions. The current launcher includes read-only direnv approval access, writable LMDB and extension state, and Podman connection-file grants. The ownership migration preserves these integrations.

## Existing-profile ownership migration

This migration configures nono through Nix. It does not implement the protection contract below or complete any selective-protection slice.

- The module generates the existing static profile as a Nix store file and exposes it through `environment.etc."nono/pi.json"` on both platforms. User-relative paths remain nono runtime expansions.
- The Stow launcher prefers `/etc/nono/pi.json`. It uses the existing local profile only when the system profile has not been deployed. Broken installed symlinks, non-file entries, and access errors do not select the fallback. Nono rejects malformed profile content.
- Runtime reference, Stow-target, cache, direnv, and Podman grants remain launcher-owned. Networking, broad writable grants, first-position `--no-sandbox`, and marker-based nested-launch handling are unchanged.
- `/etc/nono/pi.json` was absent on `rvn-mac` during implementation. No host was activated, so this host continues to use the local profile until an operator deploys the Nix configuration.

### Compatibility window

| Nix revision | Launcher revision | Selected profile |
| --- | --- | --- |
| Old | Old | Existing Stow profile |
| Old | New | Existing Stow profile through the migration fallback |
| New | Old | Existing Stow profile through the old launcher |
| New | New | `/etc/nono/pi.json` |

Keep the profile permissions aligned during this window. The generated policy currently matches the local profile as parsed JSON. Profile-selection regression tests cover the new launcher's installed and absent system-profile cases; full host builds and fresh sandbox launches have not been verified.

Remove the fallback and local profile after every development host has deployed the system profile and uses the updated launcher. Remove them before any selective-protection policy diverges from the existing permissions. A later hardened launcher must require its Nix-owned policy rather than downgrade to this permissive profile.

### Verification and remaining work

- The targeted dotfiles `test:pi-nono` devenv task passed all 41 launcher and reference tests. Its retry used disposable `XDG_DATA_HOME` state without modifying the existing devenv state directory.
- Six module assertions passed with native nixpkgs packages for each of Darwin and NixOS. Both generated profiles matched the existing local profile. Nono `0.74.0` validated the generated JSON and group references and rejected malformed JSON.
- Scoped Statix, Deadnix, nixpkgs-fmt, and Biome checks passed.
- The full Pi typecheck reported errors outside the touched files in `extensions/prompt-ui/subagent-session-links.ts` and the installed `pi-hashline-edit-pro` sources. These files were left unchanged.
- Full host evaluation remains blocked. An offline evaluation of `rvn-mac` and `rvn-pc`, extended with the untracked module without staging files, timed out after 60 seconds. Evaluation of the isolated module is not full host verification.
- Fresh Seatbelt testing is unavailable in this session. The kernel reported inherited sandboxing, and nono's supervised child failed to apply a new sandbox with `Operation not permitted`. Linux enforcement is also unverified.

## Ownership and proposed layout

- The feature declaration is `modules/development/ai/nono.nix`. It contributes to `flake.modules.nixos.development` and `flake.modules.darwin.development` without importing siblings. The current system-owned profile needs no Home Manager contribution.
- Keep Pi packaging and its existing patches owned by `ai/pi/default.nix`. Nono installation has moved out of the generic AI package list into its owning module.
- Nix owns the enforcement policy and package selection. Stow retains ownership of hand-maintained launcher and shell files. Home Manager owns any generated user configuration at an explicit, non-conflicting path.
- Ordinary Nix-generated policy artifacts may reside in the store. This does not require moving the protected live dotfiles there. Define one authoritative protection policy rather than two editable copies that can disagree.
- The unfinished `nono/tests` suite was removed. With no local supporting files, the feature uses the single-file `nono.nix` layout.
- Derive user and host paths through existing module context. Resolve live Stow targets at launch, not by inspecting a home directory during pure Nix evaluation.

References: [module authoring](../module-authoring.md), [dendritic conventions](../dendritic-core.md), and [dotfiles ownership](../dotfiles-policy.md).

## Protection contract

### Candidate protected set

This is the starting inventory, not a complete allowlist ready for deployment.

| Area | Required inventory |
| --- | --- |
| Pre-sandbox execution | `.pi/agent/bin/pi`, `.pi/agent/lib/nono-launch.ts`, imported reference-resolver modules, the resolved Pi library dependencies, and runtime/module-resolution configuration that can change which code executes. |
| Policy and grants | `.pi/agent/lib/nono/pi.json`, generated enforcement configuration, and the settings, trust records, documentation-cache metadata, and symlinks that can influence the next launch's grants. |
| Selected host startup | `.config/fish/config.fish` and `.shinit`, their deployed aliases, and directly sourced inputs needed to make the selected protection meaningful. Additional Fish autoload/startup locations require an explicit scope decision. |
| Replacement paths | Existing aliases, canonical targets, and ancestor operations that could redirect or replace a protected entry. Include currently absent protected leaves and alternate links. |

Preserve reads where Pi needs them. A rule that denies all access is not interchangeable with a write restriction. Likewise, adding a read-only grant does not cancel write access inherited from a broader grant.

Prevent overwrite, append, truncation, unlink, rename-over, symlink substitution, and ancestor replacement. Test metadata changes and hard-link aliases too. Do not block ordinary sibling-file creation or atomic saves merely to make the protected-file test pass.

Keep session data and required caches writable. Where one JSON file mixes mutable preferences with authority to widen grants, choose an explicit ownership split or approval mechanism before implementation; filesystem rules cannot protect individual JSON fields.

Validate new launches against current canonical targets. Reject unsafe path resolution or policy errors rather than falling back to direct execution. Do not use polling or repair-after-write as a substitute for enforcement.

### Unresolved design gates

1. **Linux enforcement.** Landlock permissions are additive. A writable ancestor cannot be made safe by adding a read-only child grant. Evaluate narrow grants without writable protected ancestors, and a separate filesystem boundary with protected read-only paths. Any enumeration approach must handle new entries, races, renames, and existing broad runtime grants. Select an additional tool only after reviewing repository preferences and getting approval. If no approach meets the contract, leave Linux rollout blocked rather than claim parity.
2. **macOS write-denial support.** Verify the pinned nono version's policy support and generated Seatbelt rules, including precedence, alias handling, and replacement operations. Use a narrow platform-specific rule only if supported and tested; do not assume `filesystem.deny` preserves required reads.
3. **Dependency and startup coverage.** Trace the code actually loaded before confinement, including package discovery, runtime configuration, environment overrides, and sourced shell inputs. Ask for approval if meaningful protection requires substantially broader read-only areas than the selected files.
4. **Nested launch verification.** Determine how to verify the required inherited confinement on each platform. The existence or contents of an environment marker are not proof; merely detecting some sandbox is not proof of the intended restrictions. Unknown state must not select an unrestricted fallback.
5. **Intentional bypass.** Decide whether to retain first-position `--no-sandbox`, replace it with a distinct operator command, or remove it. Any retained bypass is explicitly outside the hardened entry point's guarantee and cannot remove an existing child's kernel restrictions.
6. **Grant authorization.** Decide which settings remain writable and how a user approves external write grants. Reference discovery and project trust must not silently authorize arbitrary external writes. Read-only references are the proposed default; workflows that edit `~/nixos` need an explicit write grant.

## Implementation slices

All slices below are pending. Runtime tests use disposable fixture homes and repositories, never production startup files.

### Slice 1: Demonstrate selective protection on each target platform

**Depends on:** approval of the exact protected-set scope and platform mechanism.

**Outcome:** A fixture permits ordinary edits while rejecting changes to a selected launch dependency through every tested alias and replacement path.

- Complete the dependency and policy-input inventory with an owner, access mode, and reason for each entry.
- Test the candidate enforcement against the pinned nono package and effective default/runtime groups, not just the locally authored JSON.
- On Linux, prove that no broad writable grant restores forbidden access. On macOS, verify write denial without breaking necessary reads.

**Acceptance:** The file-operation cases in the verification matrix pass on real macOS and Linux hosts, or the unsupported platform remains explicitly blocked. This slice does not change the active launcher.

### Slice 2: Launch Pi under the Nix-owned protection policy

**Depends on:** slice 1 for the platform being enabled.

**Outcome:** The ordinary `pi` entry point uses the tested policy while protected files remain live Stow-managed files.

- Add the feature module and its evaluated-policy tests. Keep NixOS, Darwin, and Home Manager ownership colocated.
- Update the dotfiles launcher to consume the authoritative policy without allowing writable local profile fragments or environment overrides to weaken it.
- Preserve Pi's existing package patches and reject unsupported policy/configuration versions.
- Keep one active entry-point contract and avoid PATH recursion or a legacy wrapper shadowing the new integration.

**Acceptance:** Required reads and ordinary project writes succeed; launcher, policy, and selected startup mutations fail. Missing or invalid enforcement configuration prevents startup. No claim of support is based on Nix evaluation alone.

### Slice 3: Prevent nested-launch and next-launch grant bypasses

**Depends on:** slice 2 and decisions on nested verification, bypass, and grant authorization.

**Outcome:** Nested agents run within the same or stricter boundary, and agent-written state cannot silently widen a later launch.

- Replace the marker-only branch with the chosen verified contract.
- Test forged, missing, stale, and malformed markers from both confined and ordinary parent processes.
- Separate authority-bearing inputs from writable session/preferences data as required by the selected design.
- Preserve explicitly approved external writes while preventing documentation paths or changed symlink targets from manufacturing new grants.

**Acceptance:** A forged `NONO_CAP_FILE` never skips required top-level confinement; nested arguments remain intact; explicit bypass behavior matches the approved contract; policy errors fail closed.

### Slice 4: Preserve normal Pi workflows without reopening protection

**Depends on:** slices 2 and 3.

**Outcome:** Pi remains usable with narrowly scoped writable state.

- Exercise session creation/resume, required authentication-state updates, extension loading, hashline state, FFF/LMDB searches, direnv approval reads, and nested agent launch using non-secret fixtures.
- Check both Stow aliases and canonical paths for each required integration.
- Remove or narrow broad grants only with an observed replacement for the workflow they support.

**Acceptance:** These workflows pass while the mutation suite still fails every forbidden operation. Report any intentionally disabled trust or settings update rather than hiding it behind a permissive fallback.

### Slice 5: Roll out without a silent compatibility downgrade

**Depends on:** all applicable platform and workflow checks.

**Outcome:** Reviewed Nix and dotfiles revisions activate predictably and identify unsupported combinations.

- Define the cross-repository compatibility window required by the dotfiles ownership policy. Test old/new Nix and launcher combinations, rejecting combinations that cannot enforce the promised policy.
- Give transitional code a removal condition. Do not overwrite unknown files or symlinks; validate generated-file ancestors before activation.
- Revalidate paths after Stow changes and prove that a normal user outside nono can still edit the protected files.
- Require operator review before activation. The agent must not automatically activate a security-policy change it proposed.
- Document recovery and rollback. A rollback to the old permissive policy must be identified as a security downgrade, not a successful hardened rollout.

**Acceptance:** Supported revision combinations pass; unsupported combinations fail clearly; host-specific runtime evidence is recorded before enabling each platform.

## Verification matrix

| Case | Required result |
| --- | --- |
| Protected file overwrite, append, and truncation | Denied; original bytes unchanged. |
| Unlink, rename-over, directory rename, or symlink replacement | Cannot replace or redirect a protected input. |
| Stow alias, canonical path, and alternate hard link | Same effective protection; unsupported alias cases are reported as blockers. |
| Missing protected leaf and path changed during launch | Cannot create a new unprotected authority input or win a resolution race. |
| Read protected launcher dependency | Allowed where required; protected credential paths remain denied. |
| Edit/create/atomically save an ordinary sibling file | Allowed. |
| Broader CWD, agent-directory, or cache grant | Does not reopen the protected set. |
| Forged marker in an unsandboxed parent | Does not bypass sandbox creation. |
| Nested raw Pi or explicit bypass inside confinement | Cannot remove inherited restrictions. |
| Writable references/settings changed between launches | Cannot silently broaden authority. |
| User edits outside nono | Allowed without moving live files into the store. |
| Nix evaluation succeeds but runtime test is unavailable | Platform remains unverified, not accepted. |

Contribute evaluated module assertions through `perSystem.nix-unit.tests` and platform checks through the existing check conventions. Keep new JavaScript/TypeScript tests in neighboring `__tests__` directories. Use the dotfiles `devenv test` integration for launcher regressions; run Nix formatting/linting and targeted host evaluations for implementation changes. Cross-platform evaluation is not a substitute for on-host enforcement tests.

## Completion and residual risk

Implementation is complete only when each enabled platform has actual mutation-denial and workflow evidence, the protected set has been reviewed, and the compatibility window is documented. Permission queries are useful diagnostics, but do not replace destructive-operation tests against disposable fixtures.

Other editable live configuration, unfiltered networking, reachable unsandboxed services, and user-approved execution or deployment remain outside this guarantee. The plan does not address kernel vulnerabilities or establish that existing mutable files were trustworthy before the first hardened launch. Review those files before using them as the initial trusted baseline.

Finish full host verification and obtain operator review before deploying the ownership migration. The next selective-protection action remains slice 1. Resolve its design gates before enabling a restrictive policy.
