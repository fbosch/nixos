# Use Tiered System Service Startup

**Status:** proposed
**Date:** 2026-07-22

## Context

`rvn-srv` starts many application containers as part of `multi-user.target`. Cold boots showed that concurrent Podman initialization creates substantial I/O contention: PriceGhost PostgreSQL provisioning took 11-17 seconds during boot but 252 milliseconds during an idle restart. DNS, VPN, and Helium need early availability, while most application services do not need to delay host startup.

## Decision

Use three startup tiers for explicitly registered server applications. Essential services start during boot; Standard services start after `multi-user.target` without gating it; Background services start later in a deterministic, staggered order. The initial policy keeps DNS, VPN, and Helium Essential; places the media stack, Linkwarden, and OpenMemory in Standard; and assigns remaining application services to Background.

## Alternatives Considered

Starting every service from `multi-user.target` was rejected because it makes all container initialization compete during boot. A single deferred tier was rejected because it creates the same resource spike after boot. A PriceGhost-specific delay was rejected because service priority is a host policy, not an application-specific concern.

## Consequences

`multi-user.target` can complete without waiting for nonessential applications, while DNS, VPN, and Helium remain available early. Standard and Background services become available later, and Background failures must be observable without blocking later applications. The flake needs a shared host-facing startup-policy module and container modules must resolve their install targets through that policy.
