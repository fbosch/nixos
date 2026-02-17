# Firejail Profile Guidance

Use upstream Firejail profiles by default instead of creating full custom profiles.

## Key fact

The Firejail project publishes and maintains many application profiles in the upstream repository (`netblue30/firejail`), including common desktop apps and browsers.

Examples:

- `chromium.profile`
- `bitwarden-desktop.profile`
- `vlc.profile`
- `signal-desktop.profile`
- `steam.profile`
- `zen-browser.profile`

## Recommended approach in this repo

1. Start with an upstream profile (for example `${pkgs.firejail}/etc/firejail/chromium.profile`).
2. Add minimal local overrides only when a concrete breakage is observed.
3. Prefer profile-local includes (`*.local`) or tiny wrapper-specific adjustments over copying and forking full upstream profiles.

## GTK theme note

Before adding GTK-related whitelists manually, verify whether they are already covered by upstream includes. Common GTK theme and settings paths are often already allowed through shared include files.
