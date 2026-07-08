# Use dnsmasq for ordered DNS fallback on rvn-srv

**Status:** accepted
**Date:** 2026-07-08

## Context

`rvn-srv` needs local DNS to prefer LAN resolvers while keeping NextDNS available as a fallback. `systemd-resolved` does not provide this policy with `FallbackDNS=`, because fallback DNS is only used when no other DNS server information is known. Adding NextDNS as another `DNS=` server also does not work, because `systemd-resolved` treats configured servers as equivalent within a lookup scope and may stick to any server after errors.

## Decision

Use `dnsmasq` on `127.0.0.1:53` as the host resolver for `rvn-srv`. Configure `dnsmasq` with `strict-order` so it forwards to `192.168.1.46`, then `192.168.1.202`, then NextDNS on `127.0.0.1:5553`. Move NextDNS off port 53 so it acts only as the final upstream in the ordered chain.

## Alternatives Considered

Use `systemd-resolved` `FallbackDNS=127.0.0.1`. This does not provide failover while LAN DNS servers are configured.

Add NextDNS as the last normal DNS server. This makes it a peer in the same resolver scope, not a strict fallback, and can route queries through NextDNS after transient errors.

Point applications directly at LAN DNS through `/etc/resolv.conf`. This keeps behavior simple but provides no local policy layer for ordered fallback.

## Consequences

DNS resolution now has one local entry point: `127.0.0.1:53`. The ordered upstream policy lives in `dnsmasq`, while NextDNS remains available on `127.0.0.1:5553` only when the LAN resolvers do not answer.

This adds one small service to the DNS path and makes `dnsmasq` part of host networking. Valid answers such as `NXDOMAIN` from LAN DNS do not fall through to NextDNS; fallback only covers upstream failure or timeout behavior.
