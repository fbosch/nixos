# Block AF_ALG in container services

**Status:** accepted
**Date:** 2026-05-01

## Context

The container service modules under `modules/services/containers/` run application workloads through Podman Quadlet units. Several services expose HTTP interfaces, mount the Podman socket, or require elevated container privileges, so a compromise inside one of these workloads should have as little kernel attack surface as practical.

The [Copy Fail](https://copy.fail/) vulnerability, CVE-2026-31431, demonstrated a reliable Linux local privilege-escalation path using the kernel crypto userspace API through `AF_ALG`. Its mitigation guidance recommends blocking `AF_ALG` socket creation for untrusted workloads such as containers and sandboxes regardless of patch state.

`AF_ALG` is rarely needed by normal web application containers. Workloads that explicitly use userspace access to the kernel crypto API, such as libkcapi or OpenSSL AFALG engine configurations, can be evaluated separately if they appear.

## Decision

Block `AF_ALG` socket creation in all container Quadlet service units by adding these systemd service restrictions:

```ini
RestrictAddressFamilies=~AF_ALG
SystemCallArchitectures=native
```

Apply this at the container unit level instead of disabling the kernel crypto userspace API host-wide. The service-level restriction limits blast radius for containerized workloads while keeping host compatibility and rollback simple.

## Alternatives Considered

Disable `CONFIG_CRYPTO_USER_API*` in the kernel. This is stronger, but it requires a custom kernel configuration, affects all host workloads, and is harder to roll back than a service-level sandboxing rule.

Blacklist `af_alg` and `algif_*` kernel modules. This is simpler than rebuilding the kernel but only works when support is modular and not already loaded. It is not a reliable boundary when the relevant support is built into the kernel.

Use a custom Podman seccomp profile. This would be precise and container-native, but maintaining a shared seccomp profile is heavier than the systemd address-family restriction for the current requirement.

## Consequences

Containerized services no longer get access to the AF_ALG socket family by default. This reduces exposure to kernel crypto userspace API bugs after a container compromise while preserving normal TCP, UDP, Unix socket, and Podman networking behavior.

If a future container legitimately needs AF_ALG, that module should document the requirement and override the restriction locally instead of weakening the default policy for all containers.
