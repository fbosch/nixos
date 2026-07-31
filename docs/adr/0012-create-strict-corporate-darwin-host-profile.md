# Create strict corporate Darwin host profile

**Status:** accepted
**Date:** 2026-06-12

## Context

`rvn-mac` is currently a personal Darwin host profile. It installs Tailscale, prefers Tailnet addresses for generated SSH host entries, imports personal secrets, writes personal npm and Wakatime credentials, clones personal dotfiles, starts Podman automatically, and uses personal Nix binary cache infrastructure.

A KMD-issued Mac has a different risk profile. The machine is expected to stay compatible with corporate endpoint management and VPN policy. Personal mesh VPNs are forbidden unless explicitly approved, so Tailscale must not be present or used. Developer tooling, containers, Homebrew, and AI tooling are still required for work, but credentials and remote-access paths should be narrower than on personal machines.

KMD's exact MDM baseline is not known. The local Nix configuration should therefore avoid managing controls that are likely owned by MDM, and it should avoid adding personal network, secret, or remote-access behavior that would be hard to justify on a company-issued device.

## Decision

Create a separate Darwin host profile for the KMD machine, named `kmd-mac`, instead of overloading the personal `rvn-mac` profile. The flake output name is independent of the MDM-managed macOS hostname.

The corporate profile will be strict by default:

- Do not install Tailscale.
- Set host metadata so Tailnet routing is disabled: no Tailnet address and `useTailnet = false`.
- Do not generate SSH host entries for personal/home machines.
- Do not install personal SOPS secrets, including the personal SSH private key.
- Do not globally export personal API tokens in shell startup.
- Do not install personal npm token or Wakatime/Wakapi config.
- Keep developer tools, Homebrew, container tooling, and AI tools installed for the assigned account; authenticate through work-approved credentials.
- Exclude the personal `fbosch.cachix.org` binary cache on the corporate host; keep `cache.nixos.org` and `nix-community.cachix.org` unless KMD policy later forbids community caches.

macOS hardening controls such as FileVault, firewall, password policy, screen lock, Gatekeeper, TCC, certificates, and VPN profiles are assumed to be owned by KMD's MDM unless proven otherwise. Nix should not fight those profiles.

## Alternatives Considered

Reusing `rvn-mac` with conditional flags was rejected because the personal and corporate risk profiles differ enough that accidental imports would be easy to miss. A separate host makes the compliance boundary visible in the module tree and in flake host metadata.

Removing Homebrew, containers, and AI tooling was rejected because those tools are required for work. The stricter boundary is around credentials, automatic background services, personal remote access, and forbidden VPNs, not around basic developer capability.

Keeping all personal secrets while only removing Tailscale was rejected because it leaves broad token and SSH-key exposure on a company-issued endpoint. Tools can stay installed without globally injecting personal credentials into every shell and child process.

Disabling personal dotfiles entirely was considered, but dotfiles are allowed for this setup. The safer compromise is to keep them while disabling `stow --adopt`, because adopting existing files can pull corporate-managed or work-specific config into a personal repo.

## Consequences

The corporate Mac keeps the development workflow while removing the clearest compliance conflicts: Tailscale, personal SSH reachability to home machines, global personal tokens, personal npm/Wakatime credentials, personal SSH key installation, Podman background auto-start, and the personal Cachix cache.

Account-specific setup uses `hostMeta.primaryUser` to target the assigned macOS short username. The profile does not create, rename, or alter that account. API keys, GitHub auth, npm auth, and AI-tool auth must come from work-approved flows or explicit per-project configuration.

The profile still depends on KMD policy details that are not yet known. If KMD forbids Homebrew, community Nix caches, personal dotfiles, specific AI tools, or local containers, the profile must tighten further.

The profile sets host metadata independently of `networking.hostName`, so MDM can retain ownership of the computer name. Shared Darwin modules must use this active metadata rather than infer it from the hostname.
