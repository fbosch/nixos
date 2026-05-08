# Remove system76 scheduler on rvn-pc

**Status:** accepted
**Date:** 2026-04-08

## Context

`rvn-pc` now runs a CachyOS kernel variant, which already includes scheduler-focused tuning choices. The host also uses `ananicy-cpp`, so keeping `system76-scheduler` adds another overlapping policy layer. This overlap increases the chance of conflicting process-priority behavior and makes performance troubleshooting less clear.

## Decision

Disable `services.system76-scheduler` for `rvn-pc` and keep scheduling behavior centered on the CachyOS kernel plus existing ananicy rules. Apply the host-level override with `lib.mkForce false` so it wins over the shared system module default.

## Alternatives Considered

Keep `system76-scheduler` enabled alongside CachyOS tuning. This preserves current behavior but keeps redundant tuning layers and potential policy conflicts. Another option was to disable `ananicy-cpp` instead, but ananicy remains useful for workload-specific process classification already in use on this host.

## Consequences

Scheduling policy on `rvn-pc` is simpler and easier to reason about, with one fewer background scheduler service. Performance issues are easier to attribute because there is less overlap in tuning mechanisms. If interactive responsiveness regresses, re-enabling `system76-scheduler` remains a straightforward rollback.
