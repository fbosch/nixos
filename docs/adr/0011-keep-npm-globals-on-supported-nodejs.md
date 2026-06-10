# Keep npm globals on supported Node.js

**Status:** accepted
**Date:** 2026-06-10

## Context

The Home Manager `development/npm-globals` module installs lockfile-pinned global npm tools with pnpm during activation and through helper commands such as `pnpm-global-install`.

On `rvn-mac`, pnpm global installs under Node.js 24 can emit repeated non-fatal warnings like:

```text
Warning: File descriptor N closed but not opened in unmanaged mode
Warning: File descriptor N opened in unmanaged mode twice
```

Temporarily switching the installer runtime to Node.js 22 reduced this warning noise, but Node.js 22 is EOL. We should not pin activation tooling to an unsupported runtime just to suppress noisy but non-fatal warnings.

## Decision

Keep the npm globals installer on the current supported Node.js line from nixpkgs, currently `nodejs_24`.

Treat Node.js unmanaged file descriptor warnings during pnpm global installs as non-fatal unless they start causing install failures, corrupted global package state, or broken generated shims.

## Alternatives Considered

Downgrading the installer to `nodejs_22` was rejected because it depends on an EOL runtime and would make security posture worse for activation-time tooling.

Suppressing warnings globally with `NODE_OPTIONS` was rejected because it can hide unrelated Node.js runtime warnings from installed package scripts and postinstall hooks.

## Consequences

Activation and `pnpm-global-install` may still print unmanaged file descriptor warnings on Darwin while using Node.js 24. This is acceptable noise until upstream Node.js or pnpm resolves the behavior.

Future fixes should prefer upstream package/runtime updates or narrowly scoped pnpm invocation changes over downgrading Node.js.
