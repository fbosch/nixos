# Restrict Nix GitHub token access to root

**Status:** accepted
**Date:** 2026-04-19

## Context

The Nix access token template was previously readable by the `wheel` group to simplify local administration. That widened exposure of a high-value credential beyond the process that needs it for authenticated fetches. We want least-privilege defaults for system-level secrets on both NixOS and Darwin hosts.

## Decision

Restrict the `github-token` secret and the generated `nix-github-token` template to root-only permissions for system configurations. Keep Home Manager user-scoped secret usage unchanged for user tooling that explicitly consumes `github-token`. Add assertions to prevent reintroducing wheel-readable permissions for the Nix template.

## Alternatives Considered

Keeping `wheel` readability was considered, but it unnecessarily expands credential access to all admin users. Creating a dedicated shared group for token readers was also considered, but current usage does not require multi-user read access. Storing the token in per-user shell configuration only was rejected because Nix daemon/system fetch paths still require a system-level include.

## Consequences

Credential blast radius is reduced for system builds and fetches, and the policy now matches least-privilege hardening goals. The main tradeoff is less convenience for ad hoc token inspection by non-root users. Future changes that need broader access must be explicit and should use narrowly scoped permissions rather than `wheel` defaults.
