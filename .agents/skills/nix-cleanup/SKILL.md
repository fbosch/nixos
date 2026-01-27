---
name: nix-cleanup
description: Run janitorial cleanup for this flake with dendritic-aware linting. Use when preparing to commit, when CI fails on lint errors, or when user asks to "clean up code", "run lints", "fix warnings", or "check flake". Handles statix/deadnix with proper exclusions and resolves conflicts with dendritic pattern.
---

# Nix Cleanup

Run cleanup and linting for this dendritic NixOS flake with awareness of repository-specific conventions and pattern conflicts.

## This Repository's Cleanup Rules

### Use Repository Lint Commands

This repository has custom lint infrastructure that respects exclusions:

**Primary command**: `nix run .#lint`
- Runs statix with `--ignore '.agents/**'`
- Runs deadnix with `--exclude '.agents'`
- Runs nixpkgs-fmt check
- Shows colored output with gum

**Format command**: `nix run .#fmt`
- Auto-formats all Nix files with nixpkgs-fmt
- Respects repository structure

**Pre-commit hook**: Automatically installed in dev shell
- Runs on `git commit`
- Formats staged files
- Runs full lint check
- Prevents commit if lints fail

### Files and Directories to Skip

**Always excluded** (configured in lint scripts):
- `.agents/skills/**` - Template code with placeholders like `<SERVICE-NAME>`
- Files with intentionally invalid Nix for demonstration

**Review carefully before touching**:
- `modules/flake-parts/hosts.nix` - Central loader, manual imports may be intentional
- `modules/flake-parts/lib.nix` - Helper functions used by loader
- Files prefixed with `_` - Work-in-progress code intentionally not imported
- `secrets/` - Never lint or modify secrets

## Dendritic Pattern vs Linter Conflicts

Statix and deadnix don't understand the dendritic pattern. Here's how to resolve conflicts:

### Conflict 1: Enable Options

**Statix suggests**:
```nix
# Statix: "Consider using mkEnableOption"
options.myFeature.enable = lib.mkEnableOption "myFeature";
config = lib.mkIf cfg.enable { ... };
```

**Dendritic pattern requires**: Import-to-enable (no enable options)
```nix
# Correct dendritic pattern
flake.modules.nixos.myFeature = {
  services.myFeature.enable = true;  # Enabled by default
};
```

**Resolution**: **REJECT statix suggestion**. Modules in this repo are correct.

**Exception**: Containerized services (in `services/containers/`) conventionally use enable options due to heavier lifecycle management.

### Conflict 2: Manual Inherit

**Statix suggests**: Removing "manual inherit" in loader files

**Dendritic loaders need**: Explicit `inherit` for clarity in import resolution

**Resolution**: 
- Skip statix fix in `modules/flake-parts/` directory
- Or use: `statix fix --ignore manual_inherit`

### Conflict 3: Unused Arguments

**Deadnix flags**: Unused `inputs` or `config` arguments

**Dendritic modules often need**: These for future extensibility or flake-parts structure

**Resolution**:
- In loader files (`flake-parts/`): Keep arguments, they're infrastructure
- In feature modules: Safe to remove if truly unused
- Use `_` prefix for intentionally unused: `{ _config, lib, ... }: ...`

### Conflict 4: Repeated Keys

**Statix flags**: Multiple definitions of same attribute

**Collector pattern uses**: Same aspect name across files (configs merge)

**Resolution**: This is correct! Collector pattern intentionally defines same name in multiple files.
- Example: `flake.modules.nixos.syncthing` defined in base module AND each host
- Configs merge via `lib.mkMerge` automatically

## Flake Check Error Patterns

When `nix flake check` fails, diagnose the pattern:

### "infinite recursion detected"

**Likely cause**: Conditional imports (dendritic anti-pattern)

**Example**:
```nix
# ❌ Causes infinite recursion
imports = lib.mkIf someCondition [ someModule ];
```

**Fix**: Load `dendritic-pattern` skill to diagnose and fix conditional import issues

### "attribute 'X' already defined"

**Likely cause**: Collector pattern conflict without `lib.mkDefault`

**Example**:
```nix
# Two modules define same value without merge strategy
# Module A: services.myapp.port = 8080;
# Module B: services.myapp.port = 9090;
```

**Fix**: Base module should use `lib.mkDefault`, host overrides without

### "attribute 'X' missing" or "option does not exist"

**Likely cause**: Cross-class import (nixos → darwin or vice versa)

**Example**:
```nix
# ❌ Importing NixOS module into Darwin context
flake.modules.darwin.myFeature = {
  imports = [ config.flake.modules.nixos.someFeature ];
};
```

**Fix**: Extract shared code to `generic` class, import generic into both

### "expecting lambda" or type errors in loader

**Likely cause**: Malformed flake-parts module

**Fix**: Check module exports `flake.modules.<class>.<name>` correctly

## Auto-Fix Decision Tree

### Safe to Auto-Apply

These fixes are safe in this repository:

✅ **Empty `let` blocks**
- Statix: Remove unused let bindings
- Safe everywhere

✅ **Formatting**
- `nix run .#fmt` 
- Safe everywhere, pre-commit handles this

✅ **Legacy syntax**
- `rec { ... }` → separate let binding
- Safe in feature modules (review in loaders)

### Requires Review Before Fixing

⚠️ **Anything in `modules/flake-parts/`**
- Loader infrastructure is delicate
- Manual imports may be intentional for debugging

⚠️ **Unused function arguments**
- In loaders: Often needed for flake-parts structure
- In modules: Check if part of dendritic signature

⚠️ **Suggestions to add options**
- Especially `mkEnableOption` suggestions
- May contradict import-to-enable pattern

⚠️ **Changes to `imports`**
- Critical for dendritic wiring
- Never auto-fix without understanding impact

⚠️ **lib.mkIf/lib.mkMerge changes**
- Affects conditional logic and merging
- Can break collector patterns

### Never Auto-Fix

❌ **Files with `# statix: ignore` comments**
❌ **Template files** (already excluded)
❌ **Secrets directory**
❌ **Host hardware-configuration.nix** (generated by nixos-generate-config)

## Cleanup Workflow

### 1. Run Lint Check

```bash
nix run .#lint
```

Review output and categorize:
- Count errors by type
- Identify which are safe vs need review
- Check if any conflict with dendritic pattern

### 2. Analyze Conflicts

For each error, ask:
- Is this a dendritic pattern conflict? (enable options, collector pattern, etc.)
- Is this in a loader file? (needs extra care)
- Is this safe to auto-fix per decision tree?

### 3. Get Approval

Present findings:
```
Found 15 issues:
  - 8 safe fixes (formatting, empty let blocks)
  - 5 enable option suggestions (REJECT - dendritic conflict)
  - 2 unused arguments in loader (KEEP - infrastructure)

Auto-apply 8 safe fixes?
```

### 4. Apply Fixes

**For safe fixes**:
```bash
nix run .#fmt  # Format
# Manual fixes for specific issues
```

**For statix fixes** (carefully):
```bash
# Review each fix before applying
statix fix --ignore '.agents/**' <specific-file>
```

**For deadnix** (carefully):
```bash
# Only in non-loader files
deadnix -e --exclude '.agents' <specific-file>
```

### 5. Re-run Checks

```bash
nix run .#lint
nix flake check --no-build  # Verify no eval errors
```

### 6. Report Results

Summary of:
- Fixes applied
- Issues rejected (with reason)
- Remaining issues requiring manual attention

## NEVER Do When Running Cleanup

**NEVER auto-apply mkEnableOption suggestions**

```nix
# ❌ Statix suggests this - REJECT IT
options.myFeature.enable = lib.mkEnableOption "myFeature";
config = lib.mkIf cfg.enable { ... };

# ✅ Dendritic pattern (correct for this repo)
flake.modules.nixos.myFeature = {
  services.myFeature.enable = true;  # Import-to-enable
};
```

**Why**: Breaks dendritic import-to-enable pattern. Features activate via imports, not enable options (except containers).

---

**NEVER run cleanup on template files**

```bash
# ❌ WRONG
statix fix .agents/skills/flake-module-creator/assets/
```

**Why**: Templates contain placeholders like `<SERVICE-NAME>` which are intentionally invalid Nix syntax. Already excluded via `--ignore '.agents/**'`.

---

**NEVER auto-fix loader files without careful review**

Files requiring extra care:
- `modules/flake-parts/hosts.nix`
- `modules/flake-parts/lib.nix`
- `modules/flake-parts/meta.nix`

**Why**: Central infrastructure. Manual imports, explicit inherits, and unused arguments may be intentional for:
- Debugging import resolution
- Future extensibility
- Flake-parts module signature

Breaking loader breaks entire flake.

---

**NEVER ignore flake check failures**

```bash
# ❌ WRONG - Suppressing without diagnosis
# (just run fmt and ignore flake check errors)
```

**Why**: `nix flake check` catches:
- Infinite recursion (conditional imports)
- Missing options (cross-class imports)
- Type errors (malformed modules)

These indicate dendritic pattern violations. Fix root cause, don't suppress.

---

**NEVER modify dotfile-managed program configs**

See [docs/agents/dotfiles-policy.md](../../docs/agents/dotfiles-policy.md) for complete list.

**Programs managed in ~/dotfiles** (never configure here):
- Shell: Fish, Zsh, Bash
- Editors: Neovim, VSCode/Cursor  
- Terminal: Kitty, Foot, WezTerm
- Desktop: Hyprland, Waybar, Rofi, etc.
- CLI tools: Bat, Btop, Lazygit, etc.

**Why**: Configuration lives in separate dotfiles repo. NixOS only installs packages, never configures these programs.

---

**NEVER apply fixes that change `imports` without understanding impact**

```nix
# ❌ DANGEROUS - Removing "unused" import
imports = [
  # config.flake.modules.nixos.baseModule  # Statix: unused?
];
```

**Why**: Imports are the dendritic wiring. Removing imports can:
- Break feature composition
- Lose collector pattern contributions
- Break multi-context module includes

Always verify import is truly unused by checking what it provides.

---

**NEVER fix "repeated keys" in collector patterns**

```nix
# Multiple files define same aspect - THIS IS CORRECT
# modules/services/syncthing.nix
flake.modules.nixos.syncthing = { ... };

# modules/hosts/host1.nix - SAME NAME, intentional
flake.modules.nixos.syncthing = { ... };
```

**Why**: Collector pattern intentionally uses same aspect name across files. Configs merge automatically via `lib.mkMerge`. Statix flags this as error but it's correct dendritic pattern.

## Reference Documentation

When cleanup reveals dendritic pattern issues:

- **Load [../dendritic-pattern/SKILL.md](../dendritic-pattern/SKILL.md)** - For pattern validation and diagnosis
- **Load [../flake-module-creator/SKILL.md](../flake-module-creator/SKILL.md)** - If creating new modules to fix issues
- **Read [docs/agents/dotfiles-policy.md](../../docs/agents/dotfiles-policy.md)** - For dotfile-managed program list

## Safety Guidelines

- Ask before applying fixes that touch `imports`, `options`, or loader files
- Present summary of findings before auto-fixing anything
- Report dendritic pattern conflicts explicitly
- When uncertain, load dendritic-pattern skill for validation
- Never modify secrets or hardware-configuration.nix
