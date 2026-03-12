# Fish Secret File Permissions

**Status:** accepted
**Date:** 2026-03-12

## Context

SOPS keeps secrets encrypted in the repository, but they are decrypted at activation/runtime for real use. The Home Manager fish activation writes plaintext environment exports to `~/.config/fish/private.fish`, which previously had no explicit restrictive permission enforcement. That creates avoidable local exposure risk if file modes or defaults are too permissive.

## Decision

Enforce secret-file hardening for fish by writing `private.fish` under a restrictive umask and explicitly setting mode `0600` after generation. This keeps readability limited to the owning user while preserving normal fish behavior for that user.

## Alternatives Considered

Leave the current behavior and rely on default umask and filesystem defaults. This was rejected because defaults vary and are easier to drift over time. Use a broader mode such as `0644` or group-readable permissions; this was rejected because the file contains plaintext secret material and does not need shared read access.

## Consequences

Plaintext secret exposure to other local users is reduced with minimal operational impact. Fish continues to load and use the file as before for the owner account. Follow-on work includes applying the same permission policy to other generated secret-bearing user files and documenting the standard in decision records.
