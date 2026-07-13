# Use ordered DNS fallback with NextDNS

**Status:** accepted
**Date:** 2026-07-13

## Context

`rvn-srv` and `rvn-pc` need to prefer the two LAN DNS resolvers while retaining NextDNS when they cannot answer. `systemd-resolved` fallback DNS only applies when no DNS server is configured, so it cannot enforce this order.

## Decision

Use `dnsmasq` on `127.0.0.1:53` as the sole host resolver. Configure `strict-order` with the LAN resolvers first and the local NextDNS proxy on `127.0.0.1:5553` last; log dnsmasq query forwarding on `rvn-pc` so the active upstream is visible in the journal.

## Alternatives Considered

Use `systemd-resolved` `FallbackDNS=`. It does not fail over while NetworkManager supplies LAN DNS servers.

Add NextDNS as another NetworkManager DNS server. This makes it a peer rather than a strict fallback and can select it during transient LAN failures.

## Consequences

Both hosts have one resolver entry point and an explicit ordered upstream policy. On `rvn-pc`, `journalctl -u dnsmasq -f` shows the server selected for each uncached query, including `127.0.0.1#5553` when NextDNS is used; those logs also retain queried domain names.
