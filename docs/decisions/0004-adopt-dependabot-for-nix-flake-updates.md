# Adopt Dependabot for Nix flake updates

**Status:** accepted
**Date:** 2026-04-08

## Context

The repository already automates dependency updates through Renovate for container images and custom package patterns, and had a separate GitHub Actions workflow for `flake.lock` updates. GitHub now supports Nix as a native Dependabot ecosystem, which can open focused pull requests per outdated flake input. Running both systems for the same `flake.lock` concerns would duplicate update traffic and review effort.

## Decision

Use Dependabot version updates for Nix flake inputs by adding `.github/dependabot.yml` with `package-ecosystem: "nix"`. Target the default `master` branch, assign update PRs to `fbosch`, and limit concurrent open Dependabot PRs for this ecosystem. Remove the legacy `.github/workflows/update-flake.yml` workflow so Dependabot is the single source of automated flake input updates.

## Alternatives Considered

Keep the existing `update-flake-lock` workflow and avoid Dependabot migration. This preserves current behavior but misses native Dependabot Nix integration and per-input update PR granularity. Another option was to run both in parallel, but that would create overlapping PRs and unnecessary maintenance complexity.

## Consequences

Flake input updates become standardized under Dependabot with smaller, input-scoped PRs and GitHub-native dependency tooling. The repository no longer depends on PAT/Cachix wiring in the old flake update workflow for this task. Follow-on work may include adding additional Dependabot ecosystems (for example GitHub Actions) if centralized dependency automation is desired.
