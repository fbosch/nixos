# Use Lazy Apps For Rarely Used Packages

**Status:** accepted
**Date:** 2026-06-14

## Context

Some packages are useful to have on `PATH` but are rarely used, such as one-off diagnostics, gaming helpers, and CLI/TUI tools. Keeping them in `environment.systemPackages` or `home.packages` realizes their full closures during rebuild even when they are not used.

## Decision

Use `lazy-apps` for selected rarely used packages and expose it through `config.flake.lib.lazyApp`. Prefer this for direct entries in `environment.systemPackages` and `home.packages`, using the simple form for packages with a clear executable and the attrset form when an explicit `exe` is needed.

## Alternatives Considered

Keeping all packages directly installed is simpler and fully offline after rebuild, but it adds closure size and rebuild/substitution work for tools that may not be used. `nix run`, `nix shell`, and `comma` remain useful for ad-hoc commands, but they do not make a configured command available as a normal package entry.

## Consequences

Rarely used tools can remain declarative and available on `PATH` while their real package closures are realized only on first run. First launch may require cache or network access, and garbage collection can remove realized packages if nothing else roots them. Do not use lazy wrappers for services, libraries, activation-script inputs, desktop/session infrastructure, auth/security tools, or module package options that need real package contents.
