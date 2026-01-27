---
name: nixos-debug
description: Debug failing NixOS builds and activations. Use when build fails (infinite recursion, attribute errors, evaluation errors), activation fails (systemd services, SOPS secrets, home-manager), or when asking to "debug build", "fix activation error", "why is rebuild failing", or "troubleshoot NixOS issue". Handles SOPS decryption issues, systemd service failures, and common NixOS configuration errors.
---

# NixOS Build & Activation Debugging

Debug failing NixOS builds and activations for this NixOS flake repository.

## When to Use This Skill

Trigger this skill when encountering:
- Build failures: infinite recursion, attribute errors, evaluation errors
- Activation failures: systemd services, SOPS secrets, home-manager issues
- Module configuration problems: imports not working, options missing

## Quick Diagnostic Workflow

### 1. Identify Failure Type

**Build failure** (fails before activation):
- Infinite recursion
- Attribute already defined / missing
- Type errors, evaluation errors
- Flake check failures

**Activation failure** (build succeeds, activation fails):
- Systemd service failures
- SOPS decryption errors
- Home Manager conflicts
- File system mount errors
- Boot loader errors

### 2. Get Error Context

```bash
# Recommended: Use nh CLI (better output, cleaner errors)
nh os switch --ask

# Or traditional nixos-rebuild with full trace
sudo nixos-rebuild switch --flake .#hostname --show-trace

# For flake check
nix flake check --show-trace
```

Copy the full error message including file paths and line numbers.

**Note**: This repository has `nh` (nix-helper) available, which provides cleaner output and better error messages than `nixos-rebuild`.

### 3. Match Error Pattern

Load appropriate reference based on error pattern:

**Build errors** → See [references/build-failures.md](references/build-failures.md)
- Infinite recursion
- Attribute already defined
- Attribute missing / option doesn't exist
- Expecting lambda errors
- Hash mismatches

**Activation errors** → See [references/activation-failures.md](references/activation-failures.md)
- Systemd service failures
- Home Manager activation errors
- SOPS decryption failures
- File system errors
- User/group creation errors

**Module/pattern issues** → Load [dendritic-pattern](../dendritic-pattern/SKILL.md) skill for architecture validation

**Need commands?** → See [references/diagnostic-commands.md](references/diagnostic-commands.md)

## Common Debug Patterns

### Pattern: Infinite Recursion

**Error**: `error: infinite recursion encountered`

**Most common causes**:
- Circular module imports
- Conditional imports causing evaluation loops
- Module self-references

**Diagnosis**:
1. Find file in error stack trace
2. Check imports chain for circular dependencies
3. Load [dendritic-pattern](../dendritic-pattern/SKILL.md) skill if architecture-related

**Quick check**:
```bash
# Find conditional imports
rg "imports.*mkIf|imports.*optional" modules/

# Check for circular imports
nix-instantiate --eval --strict --show-trace
```

**Detailed guide**: [references/build-failures.md](references/build-failures.md#infinite-recursion-errors)

---

### Pattern: SOPS Secrets Won't Decrypt

**Error**: `failed to get the data key required to decrypt the SOPS file`

**Quick diagnosis**:
```bash
# 1. Check age key exists
ls -la /var/lib/sops-nix/key.txt

# 2. Verify key is in .sops.yaml
cat .sops.yaml | grep -A5 'age'

# 3. Test decryption manually
nix-shell -p sops --run "sops -d secrets/secrets.yaml"
```

**Most common fix**: Age key not in `.sops.yaml` yet

```bash
# Bootstrap age key into .sops.yaml
./scripts/bootstrap-age.sh

# Commit updated .sops.yaml
git add .sops.yaml && git commit -m "Add age key for hostname"

# Rebuild
sudo nixos-rebuild switch --flake .#hostname
```

**Detailed guide**: [references/activation-failures.md](references/activation-failures.md#sops-decryption-failures)

---

### Pattern: Systemd Service Failed to Start

**Error**: `Failed to start X.service`

**Quick diagnosis**:
```bash
# Check service status and logs
systemctl status <service-name>
journalctl -u <service-name> -b

# View service configuration
systemctl cat <service-name>
```

**Common causes**:
- Missing dependencies (other services)
- Wrong user/group
- Permission errors on directories
- Binary not in PATH

**Example fix** (missing dependency):
```nix
systemd.services.myapp = {
  after = [ "network-online.target" ];
  wants = [ "network-online.target" ];
  requires = [ "postgresql.service" ];  # Add required service
};
```

**Detailed guide**: [references/activation-failures.md](references/activation-failures.md#systemd-service-failures)

---

### Pattern: Module Not Taking Effect

**Symptom**: Module file exists but configuration doesn't apply

**Quick checks**:
```bash
# 1. Is module in flake outputs?
nix flake show | grep mymodule

# 2. Does host import it?
nix eval .#nixosConfigurations.<hostname>.config.imports

# 3. Check module syntax
nix-instantiate --parse modules/mymodule.nix
```

**Common issues**:
- Module not imported by host configuration
- Syntax errors preventing module load
- Module in wrong location (not discovered by flake)
- Typo in module path

**For architecture issues**: Load [dendritic-pattern](../dendritic-pattern/SKILL.md) skill

---

### Pattern: Attribute Already Defined

**Error**: `attribute 'X' already defined at Y`

**Common causes**:
- Duplicate definitions in different files
- Missing `lib.mkDefault` for overridable values
- Using `//` instead of `lib.mkMerge` for config merging

**Diagnosis**:
```bash
# Find where attribute is defined
rg "attribute-name" modules/

# Check for shallow merge operators
rg "= .* // " modules/

# Check for missing mkDefault
rg "services\." modules/ | grep -v mkDefault
```

**Quick fixes**:
- Add `lib.mkDefault` to base value: `services.port = lib.mkDefault 80;`
- Use `lib.mkMerge` instead of `//`: `config = lib.mkMerge [ base override ];`
- Remove duplicate definition if unintentional

**Detailed guide**: [references/build-failures.md](references/build-failures.md#attribute-already-defined)

---



## Systematic Debug Process

When facing an unfamiliar error, follow this process:

### Step 1: Capture Full Error

```bash
# Recommended: Use nh for cleaner output
nh os switch --ask 2>&1 | tee error.log

# Or get complete error with trace
sudo nixos-rebuild switch --flake .#hostname --show-trace 2>&1 | tee error.log
```

Save the full output including:
- Error message
- File paths and line numbers
- Stack trace

### Step 2: Classify Error Type

**Evaluation errors** (build-time):
- "infinite recursion"
- "attribute already defined"
- "attribute missing"
- "expecting lambda"
- "undefined variable"

**Activation errors** (runtime):
- "Failed to start"
- "failed to decrypt"
- "device not found"
- "Existing file conflicts"

**Lint/check errors**:
- Statix warnings
- Deadnix warnings
- Type errors

### Step 3: Load Appropriate Reference

Based on classification:
- Build errors → `references/build-failures.md`
- Activation errors → `references/activation-failures.md`
- Need diagnostic commands → `references/diagnostic-commands.md`

### Step 4: Match Pattern and Apply Fix

1. Search reference for error message pattern
2. Review example fixes
3. Apply fix to your configuration
4. Test rebuild

### Step 5: Verify Fix

```bash
# Recommended: Rebuild with nh
nh os switch --ask

# Or rebuild with trace
sudo nixos-rebuild switch --flake .#hostname --show-trace

# If successful, verify functionality
systemctl status <affected-service>

# Check logs
journalctl -u <affected-service> -n 50
```

### Step 6: Related Issues Check

After fixing primary error:
- Run lint: `nix run .#lint`
- Run flake check: `nix flake check`
- Check for architecture issues: Load `dendritic-pattern` skill if needed

## Integration with Other Skills

**For pattern validation**: Load [dendritic-pattern](../dendritic-pattern/SKILL.md) skill
- Validates module structure
- Checks import patterns
- Verifies aspect patterns

**For cleanup after fixes**: Load [nix-cleanup](../nix-cleanup/SKILL.md) skill
- Fixes lint errors
- Cleans up formatting
- Runs repository checks

**For creating new modules**: Load [flake-module-creator](../flake-module-creator/SKILL.md) skill
- Creates properly structured modules
- Follows dendritic pattern
- Includes correct boilerplate

## Repository-Specific Context

### SOPS Setup

- Age key auto-generated at `/var/lib/sops-nix/key.txt` on first build
- Must run `./scripts/bootstrap-age.sh` to add key to `.sops.yaml`
- GPG key for manual editing (optional, from Bitwarden)

See [docs/agents/sops-secrets.md](../../../docs/agents/sops-secrets.md) for workflow.

### Lint Infrastructure

- Run with: `nix run .#lint`
- Format with: `nix run .#fmt`
- Pre-commit hook auto-installed in dev shell

### Build Tools

- **nh (nix-helper)**: Available in this repo for cleaner rebuild output
  - `nh os switch --ask` - Interactive switch with confirmation
  - `nh os build` - Build without switching
  - `nh os test` - Test without making default
  - Provides better error messages and progress indication than nixos-rebuild

See [docs/agents/linting-statix.md](../../../docs/agents/linting-statix.md) for details.

## Safety Guidelines

- Present diagnosis before applying fixes
- Ask before modifying loader files (`modules/flake-parts/`)
- Never modify secrets or hardware-configuration.nix
- Test fixes incrementally (don't batch multiple changes)
- Keep rollback option available (previous generation)

## Quick Reference: Error → Reference Mapping

| Error Pattern | Reference File |
|--------------|----------------|
| Infinite recursion | [build-failures.md](references/build-failures.md#infinite-recursion-errors) |
| Attribute already defined | [build-failures.md](references/build-failures.md#attribute-already-defined) |
| Option does not exist | [build-failures.md](references/build-failures.md#attribute-missing--option-does-not-exist) |
| Failed to start service | [activation-failures.md](references/activation-failures.md#systemd-service-failures) |
| SOPS decryption failed | [activation-failures.md](references/activation-failures.md#sops-decryption-failures) |
| Home Manager conflicts | [activation-failures.md](references/activation-failures.md#home-manager-activation-failures) |
| Need diagnostic commands | [diagnostic-commands.md](references/diagnostic-commands.md) |
