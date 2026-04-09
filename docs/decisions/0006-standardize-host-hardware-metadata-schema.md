# Standardize host hardware metadata schema

**Status:** proposed
**Date:** 2026-04-09

## Context

Host metadata is already colocated with host modules, but hardware details are not captured in a consistent machine-readable form. This creates ambiguity for automation and agent reasoning when decisions depend on CPU or platform characteristics. A stable schema is needed so host capabilities and risk-relevant hardware facts are expressed uniformly.

## Decision

Adopt a standardized hardware metadata schema within per-host metadata definitions. The schema should capture durable facts and intent (for example platform, CPU family/class, and GPU vendor/model) and explicitly exclude runtime-observed state. New and updated hosts should follow this schema going forward.

## Alternatives Considered

Centralizing all hardware data in one global file was considered, but it weakens locality and increases drift from host modules. Keeping hardware details only in prose documentation was also considered, but it is difficult for tooling and agents to consume reliably. Deferring schema definition until a full migration was rejected because it delays consistency and prevents incremental adoption.

## Consequences

Host metadata becomes easier to consume programmatically for policy checks, deployment logic, and agent workflows. Hardware-sensitive decisions can rely on explicit, structured inputs instead of comments or ad hoc conventions. The tradeoff is ongoing maintenance of metadata accuracy, while runtime validation remains a separate operational responsibility.
