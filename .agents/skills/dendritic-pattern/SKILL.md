---
name: dendritic-pattern
description: Validate dendritic Nix flake pattern usage in this repository. Use when reviewing modules, refactoring code, or checking dendritic pattern compliance. Validates flake-parts module structure, aspect-oriented design, feature organization, and adherence to dendritic principles from the Doc-Steve/dendritic-design-with-flake-parts wiki.
---

# Dendritic Pattern Validation

Validate that NixOS modules in this repository follow the dendritic pattern with flake-parts.

## Core Validation Rules

**CRITICAL RULES** (see [references/validation-rules.md](references/validation-rules.md) for complete details):

1. **Module Classes:** Every module belongs to nixos, darwin, homeManager, or generic class
2. **NO Conditional Imports:** Never use `lib.mkIf` with `imports` (causes recursion)
3. **NO Cross-Class Imports:** Can't import nixos module into darwin (use generic class)
4. **MUST Use lib.mkMerge:** Always use `lib.mkMerge` not `//` for merging
5. **Import to Enable:** Features activate when imported, not via enable options
6. **Collector Merging:** Multiple files can define same aspect name - configs merge

### Module Structure
- Every `.nix` file in `modules/` must be a flake-parts module
- Modules export `flake.modules.<class>.<aspect>` where:
  - `<class>` is `nixos`, `darwin`, `homeManager`, or `generic`
  - `<aspect>` is the feature name (usually matches file/directory name)
- Features enable by default when imported (no enable options)
- Use `lib.mkDefault` for user-overridable values

### Aspect Patterns
Check modules follow these dendritic aspect patterns:

1. **Simple Aspect** - Feature used in multiple contexts without dependencies
2. **Multi-Context Aspect** - Main module + auxiliary module for nested contexts (e.g., NixOS + Home Manager)
3. **Inheritance Aspect** - Extends parent aspect via imports
4. **Conditional Aspect** - Uses `lib.mkIf` and `lib.mkMerge` for conditional config
5. **Collector Aspect** - Aggregates config from multiple features
6. **Constants Aspect** - Provides shared values via `generic` class
7. **DRY Aspect** - Reusable components in custom module class
8. **Factory Aspect** - Parameterized functions generating module instances

See [references/aspect-patterns.md](references/aspect-patterns.md) for detailed pattern descriptions.

### File Organization
- All features in `modules/` directory
- Feature name matches file/directory name
- Complex features split into subdirectories
- No `specialArgs` usage (use `let...in` or flake-level options instead)
- Host configs use `flake.modules.nixos."hosts/<name>"` pattern

### Common Anti-Patterns

**CRITICAL violations:**

- **Conditional imports** - Using `lib.mkIf` with `imports` (causes infinite recursion)
- **Cross-class imports** - Importing wrong module class (nixos → darwin)
- **Using // for merge** - Using `//` instead of `lib.mkMerge` (shallow merge loses config)
- **Enable options** - Using enable options instead of import pattern (not dendritic)

**Design violations:**

- **Host-centric organization** - Modules organized by host instead of feature
- **Manual sibling imports** - Using relative paths like `./other-module.nix`
- **specialArgs abuse** - Passing values that should be flake-level options or let...in
- **Multiple imports** - Same module imported multiple times in one path
- **Wrong module class** - Service in programs/, program in services/

See [references/validation-rules.md](references/validation-rules.md) for complete anti-pattern catalog.

## Validation Workflow

1. **Check flake.nix**
   - Verify import-tree usage for automatic module loading
   - Ensure minimal boilerplate (inputs, flake-parts setup)
   - No manual module imports

2. **Scan modules/ directory**
   - Each file defines `flake.modules.<class>.<aspect>`
   - Aspect name matches file/directory semantic meaning
   - Features use imports, not enable options

3. **Validate module content**
   - Check proper aspect pattern usage
   - Verify no specialArgs
   - Confirm lib.mkMerge for conditionals
   - Validate import syntax uses inputs.self.modules

4. **Review feature hierarchy**
   - Features compose via imports
   - No circular dependencies
   - Proper class separation

5. **Check host/user definitions**
   - Hosts/users are features too
   - Proper boilerplate for nixosConfigurations
   - No per-host package definitions outside perSystem

## Reference Documentation

For deep pattern knowledge, load these references:

- **[references/validation-rules.md](references/validation-rules.md)** - **START HERE** - Critical implementation rules with examples
- **[references/basics.md](references/basics.md)** - Core dendritic concepts, module classes, file organization
- **[references/aspect-patterns.md](references/aspect-patterns.md)** - Detailed 8 aspect pattern catalog with examples
- **[references/faq.md](references/faq.md)** - Common questions, design decisions, and practical tips

## Reporting Findings

Report validation results with:
1. **Severity:** CRITICAL (breaks build), ERROR (violates pattern), WARNING (style issue)
2. File path and line number
3. Issue description
4. Which rule/pattern is violated
5. Recommended fix with code example
6. Reference to relevant documentation

Example report format:
```
🔴 CRITICAL: modules/services/myapp.nix:15
Issue: Conditional imports cause infinite recursion
Rule: NO conditional imports - Never use lib.mkIf with imports
Current: imports = lib.mkIf cfg.enable [ otherModule ];
Fix: imports = [ otherModule ];
     config = lib.mkIf cfg.enable { ... };
Reference: references/validation-rules.md#rule-2-no-conditional-imports

❌ ERROR: modules/programs/firefox.nix:23
Issue: Using enable option instead of import pattern
Rule: Features enable by default when imported
Current: options.firefox.enable = lib.mkEnableOption "firefox";
Fix: flake.modules.homeManager.firefox = {
       programs.firefox.enable = true;  # Enabled by default
     };
Reference: references/validation-rules.md#rule-6-features-enable-by-default

⚠️  WARNING: modules/services/nginx.nix:42
Issue: File organization doesn't follow convention
Pattern: Services should be in modules/services/
Reference: references/basics.md#file-organization
```

## Safety
- Never modify files unless explicitly requested
- Report issues first, await user confirmation
- Suggest fixes, don't apply them automatically
