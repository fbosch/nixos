# Standardize on SDDM for desktop login

**Status:** accepted
**Date:** 2026-04-19

## Context

The previous display-manager path relied on TTY/fbcon behavior, which caused login layout and centering issues on the mixed-resolution monitor setup (`DP-2` ultrawide plus `HDMI-A-2`). This made the greeter experience inconsistent and hard to tune reliably for the primary monitor.

## Decision

Adopt SDDM as the display manager for desktop login, with Wayland mode enabled and Weston used as the compositor. Keep `hyprland-uwsm` as the default session and apply host-specific Weston output configuration on `rvn-pc` to target the intended monitor behavior.

## Alternatives Considered

Keeping Ly was rejected because TTY/fbcon mode-clamping on mixed displays produced persistent positioning artifacts. Staying on greetd-based greeters remained viable for manual recovery flows, but the immediate priority was predictable multi-monitor login presentation on this host.

## Consequences

Login screen behavior is more predictable on the ultrawide setup and easier to control with compositor output rules. The tradeoff is weaker ad-hoc command-entry recovery at the greeter compared with greetd-focused workflows, so recovery patterns should rely on predefined sessions and standard TTY fallback.
