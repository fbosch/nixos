# Security Vulnerability Scanning

## Overview
Automated security scanning runs daily and on every push to detect vulnerabilities in your NixOS system packages.

## How It Works

The security workflow:
1. Builds your NixOS configuration
2. Scans the system closure with [vulnix](https://github.com/nix-community/vulnix)
3. **Fails the build** if any critical vulnerabilities (CVSS ≥ 9.0) are found
4. Reports high-severity (CVSS ≥ 7.0) issues as informational warnings
5. Respects whitelisted CVEs in `.vulnix-whitelist.toml`

## Understanding Results

### GitHub Actions Summary
Each scan produces a summary showing:
- **Total vulnerabilities**: All CVEs found (any severity)
- **High severity (CVSS ≥ 7.0)**: Informational - review when convenient
- **Critical (CVSS ≥ 9.0)**: Build-blocking issues that need immediate attention

### Build Status
- ✅ **Pass**: No critical vulnerabilities (or all whitelisted)
- ❌ **Fail**: Critical vulnerabilities found that need immediate attention

## Fixing Vulnerabilities

### Step 1: Update NixOS
Most vulnerabilities are fixed by updating nixpkgs:

```bash
# Update flake inputs
nix flake update

# Test the configuration
nixos-rebuild test

# If successful, switch to it
nixos-rebuild switch

# Commit the changes
git add flake.lock
git commit -m "Update nixpkgs to fix security vulnerabilities"
git push
```

### Step 2: Verify the Fix
The security workflow will run automatically on push. Check that it passes.

### Step 3: Handle False Positives

If a CVE doesn't actually affect your system (e.g., package name collision), add it to the whitelist:

**Edit `.vulnix-whitelist.toml`:**
```toml
[[packages]]
name = "package-name"           # From the scan results
cve = "CVE-YYYY-XXXXX"          # Specific CVE
comment = "Why this is safe"    # Detailed explanation
expiry = "2026-06-01"           # Review date (max 1 year)
```

**Common false positive patterns:**
- Haskell/Rust libraries with same names as unrelated software
- Jenkins plugins vs CLI tools (e.g., "git" plugin vs git CLI)
- Development dependencies not in runtime closure
- Python/Node packages vs system utilities

## Whitelist Management

### Best Practices
1. **Be specific**: Whitelist individual CVEs, not entire packages
2. **Document why**: Always include a clear comment
3. **Set expiry dates**: Force periodic review (max 1 year)
4. **Review regularly**: Check quarterly if entries are still valid

### Example Entry
```toml
[[packages]]
name = "vault"
cve = "CVE-2023-0620"
comment = "This CVE affects HashiCorp Vault server, not the Haskell vault library we use"
expiry = "2026-06-01"
```

## Manual Scanning

To scan locally:

```bash
# Build your system
nix build .#nixosConfigurations.rvn-vm.config.system.build.toplevel

# Run vulnix
nix run github:nix-community/vulnix -- --json --whitelist .vulnix-whitelist.toml ./result > vulnix.json

# Check for high-severity issues
jq '[ .[] | select( ([.cvssv3_basescore[]]|max) >= 7 ) ]' vulnix.json
```

## Troubleshooting

### "Too many vulnerabilities after update"
- Review the list carefully - many may be false positives
- Check package names against CVE descriptions
- Add confirmed false positives to whitelist

### "Can't find security fix"
1. Check if fix is in nixos-unstable: `nix search nixpkgs#package-name`
2. Look for tracking issues: https://github.com/NixOS/nixpkgs/issues
3. Consider package overlays for urgent fixes
4. Document as accepted risk if no fix available yet

### "Whitelist not working"
- Verify TOML syntax is correct
- Check that package name and CVE match scan output exactly
- Ensure expiry date is in the future

## Resources
- [Vulnix Documentation](https://github.com/nix-community/vulnix)
- [NixOS Security](https://nixos.org/manual/nixos/stable/#sec-security)
- [CVE Database](https://cve.mitre.org/)
- [CVSS Score Calculator](https://nvd.nist.gov/vuln-metrics/cvss)
