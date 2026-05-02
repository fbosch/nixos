# NixOS Flake Context

Domain language for this personal NixOS, Darwin, and Home Manager flake. Architecture guidance lives in the dendritic pattern references; this file names the project concepts those references apply to.

## References

- [README.md](README.md) - project overview and common tasks.
- [Dendritic core concepts](docs/agents/dendritic-core.md) - single module tree, central loader, metadata, per-system outputs, and special arguments.
- [Module authoring rules](docs/agents/module-authoring.md) - import-to-enable modules, option namespaces, and authoring conventions.
- [Container module authoring](docs/agents/container-modules.md) - Podman Quadlet module conventions.

## Language

**Flake**:
The repository-level Nix definition that exposes hosts, modules, packages, checks, and shared metadata.
_Avoid_: repo config, setup

**Dendritic module tree**:
A single flake-parts tree where feature files export under `flake.modules.*` and consumers resolve modules by attribute path.
_Avoid_: direct imports, sibling imports

**Host**:
A concrete machine configuration assembled from a list of modules and host metadata.
_Avoid_: profile, target

**Host metadata**:
Static machine intent such as name, model, fleet role, and addressing exported through `flake.meta.hosts`.
_Avoid_: runtime facts, live diagnostics

**Module key**:
The string or attribute path used to select a module from `flake.modules.*`.
_Avoid_: file path

**Import to enable**:
The convention that importing a module enables its behavior with useful defaults instead of requiring a top-level enable option.
_Avoid_: enable flag by default

**Shared metadata**:
Project-wide facts under `flake.meta` consumed by modules instead of duplicated literals.
_Avoid_: magic strings

**perSystem output**:
Architecture-specific flake output for packages, checks, development shells, and automation.
_Avoid_: ad hoc script wiring

**Container module**:
A NixOS module that defines a Podman Quadlet unit, its ports, firewall rules, data paths, and secrets wiring.
_Avoid_: docker-compose module, build service

**Exposed port declaration**:
An entry in `services.exposedPorts` used to make port ownership visible to validation.
_Avoid_: hidden listener

**SOPS helper**:
Shared library functions under `config.flake.lib.sopsHelpers` for declaring encrypted secrets with consistent permissions.
_Avoid_: repeated secret boilerplate

## Relationships

- A **Flake** contains the **Dendritic module tree**.
- A **Host** imports modules by **Module key**.
- **Host metadata** describes static intent for a **Host**.
- **Shared metadata** is read by modules to avoid duplicated literals.
- A **Container module** owns its **Exposed port declaration**.
- A **SOPS helper** is used by modules that need encrypted secret declarations.
- A **perSystem output** exposes automation for each supported system architecture.

## Example Dialogue

> **Dev:** "Should this machine import the file path directly?"
> **Domain expert:** "No. Add it to the **Dendritic module tree** and import it by **Module key** so the **Host** stays declarative."

> **Dev:** "Where should the container port be declared?"
> **Domain expert:** "The **Container module** owns the **Exposed port declaration** and firewall rule together."

## Flagged Ambiguities

- "module" can mean a Nix module or the architecture term Module. In this project context, use **Dendritic module tree** or **Module key** when discussing flake layout, and use the architecture vocabulary only during architecture reviews.
