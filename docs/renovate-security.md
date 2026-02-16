# Container Security & Updates: Renovate + Trivy

This document explains the automated container update and security scanning system for this NixOS flake.

## Overview

**Goal**: Keep container dependencies up-to-date with minimal manual effort while catching security vulnerabilities early.

**Tier 2 Security Approach**:
- **Renovate Bot**: Automatically creates PRs for container image updates, includes vulnerability alerts
- **Trivy Scanner**: Scans container images in PRs for CRITICAL/HIGH/MEDIUM vulnerabilities
- **Zero manual tracking**: Regex-based auto-discovery of all container images in Nix modules

## How It Works

### Renovate Bot (`renovate.json`)

Renovate runs on the 1st of every month at 3 AM CET and scans all Nix files for container image references using three custom regex patterns:

**Pattern 1: Hardcoded Quadlet Images**
```nix
# Matches lines like:
Image=docker.io/amir20/dozzle:latest
```

**Pattern 2: Nix Option Defaults (Full Image)**
```nix
# Matches lines like:
image = lib.mkOption { default = "docker.io/qmcgaw/gluetun:v3.40.0"; }
```

**Pattern 3: Nix ImageTag with Variable Interpolation**
```nix
# Matches combinations like:
Image=glanceapp/glance:${cfg.imageTag}
# ... plus later in the file:
imageTag = lib.mkOption { default = "latest"; }
```

When Renovate finds an outdated image:
1. Creates a PR with the updated version
2. Adds vulnerability information if known issues exist
3. Groups updates by severity (security updates bypass monthly schedule)
4. Waits for stability period on critical services (3 days)

### Trivy Vulnerability Scanner (`.github/workflows/container-security-scan.yml`)

Triggered automatically on PRs that modify files in `modules/services/containers/`:
1. Extracts container images from changed Nix files
2. Pulls each image and scans with Trivy
3. Reports CRITICAL/HIGH/MEDIUM vulnerabilities as PR comments
4. Uploads results to GitHub Security tab (Code Scanning Alerts)

### Critical Services Policy

**Services with special handling** (3-day stability wait before auto-merge):
- **Pi-hole** (DNS): Also restricted to major version updates only
- **Gluetun** (VPN): Already pinned to v3.40.0
- **Komodo Core/Periphery** (infrastructure management)
- **MongoDB** (Komodo's database backend)

**Rationale**: These services are mission-critical infrastructure. We wait 3 days after an image is published before updating to catch any immediate bugs reported by the community.

### Local-Only Images (Excluded)

These images are built locally and won't be tracked by Renovate:
- `helium` (custom build)
- `openmemory` (custom build)

You must manually update their upstream dependencies.

## How to Review & Merge Update PRs

### 1. Check the PR Description
Renovate includes:
- What changed (old version → new version)
- Release notes link
- Vulnerability information (if applicable)
- Age of the update (for stability confidence)

### 2. Review Trivy Scan Results
- Check PR comments for vulnerability scan output
- Review GitHub Security tab for detailed CVE information
- **Red flag**: CRITICAL vulnerabilities in the new image → investigate before merging

### 3. Test on `rvn-srv` First
```bash
# Checkout the Renovate PR branch
git fetch origin
git checkout renovate/some-container-update

# Rebuild on rvn-srv (lowest-risk server)
nixos-rebuild switch --flake .#rvn-srv --target-host rvn-srv --use-remote-sudo

# Monitor for 24-48 hours
# Check logs: journalctl -u <service-name> -f
# Verify service health via web UI or API
```

### 4. Merge the PR
If testing passes:
```bash
# Merge via GitHub UI, or:
gh pr merge <PR-number> --squash
```

### 5. Apply to Other Hosts (if applicable)
If the container runs on multiple hosts, deploy after successful `rvn-srv` validation:
```bash
# Desktop hosts (if needed)
nixos-rebuild switch --flake .#rvn-pc
nixos-rebuild switch --flake .#rvn-vm
```

## Security Update Workflow

**Security updates bypass the monthly schedule** and create PRs immediately.

### When You Get a Security Update PR:

1. **Assess severity**: Check Renovate's vulnerability summary
   - CRITICAL: Review within 24 hours, expedite testing
   - HIGH: Review within 48 hours
   - MEDIUM/LOW: Review within 1 week

2. **Check if exploit is relevant**:
   - Does it affect services exposed to untrusted networks?
   - Does it require authentication you already enforce?
   - Is the vulnerability in a code path you don't use?

3. **Test urgently but carefully**:
   - Don't skip testing even for CRITICAL patches
   - Security updates can introduce regressions
   - Test on `rvn-srv` first (30 minutes minimum)

4. **Roll back if needed**:
   ```bash
   # If the update breaks something:
   nixos-rebuild switch --flake .#rvn-srv --rollback
   
   # Comment on the PR why you're waiting
   # Check upstream issue tracker for known problems
   ```

## Adding New Container Services

**No manual configuration needed!** Renovate automatically discovers containers if you follow these patterns:

### Supported Patterns

**Quadlet Services** (in `environment.etc."containers/systemd/*.container"`):
```nix
Image=docker.io/some/image:v1.2.3
# Renovate will find this automatically
```

**Nix Option Defaults (Full Image)**:
```nix
image = lib.mkOption {
  default = "docker.io/some/image:v1.2.3";
};
```

**Nix ImageTag with Variable**:
```nix
# In the Quadlet definition:
Image=docker.io/some/image:${cfg.imageTag}

# In the options section:
imageTag = lib.mkOption {
  default = "v1.2.3";
};
```

### If Your Container Needs Special Handling

Edit `renovate.json`:

**Pin to major version only** (like Pi-hole):
```json
{
  "matchDatasources": ["docker"],
  "matchPackageNames": ["docker.io/your/image"],
  "versioning": "loose",
  "allowedVersions": "/^v?[0-9]+\\./"
}
```

**Add to critical services group** (3-day stability wait):
```json
{
  "groupName": "critical-services",
  "matchPackageNames": [
    "docker.io/pihole/pihole",
    "docker.io/your/critical-service"  // Add here
  ]
}
```

**Exclude from updates** (local builds):
```json
{
  "matchPackageNames": ["your-local-image"],
  "enabled": false
}
```

## Troubleshooting

### Renovate Isn't Finding My Container

**Check the regex patterns** in `renovate.json`:
```bash
# Test Pattern 1 (Quadlet hardcoded)
rg 'Image=[^:$]+:[^$\s]+' modules/services/containers/

# Test Pattern 2 (Nix image option)
rg 'image\s*=\s*lib\.mkOption' modules/services/containers/ -A 2 | rg 'default.*"[^:]+:[^"]+"'

# Test Pattern 3 (ImageTag variable)
rg 'Image=[^:]+:\$\{[^}]+\}' modules/services/containers/
```

If your pattern doesn't match, either:
1. Adjust your Nix code to match the supported patterns, OR
2. Add a new regex manager to `renovate.json`

### Trivy Scan Failing on PR

**Common causes**:
- Private registry requiring authentication → add credentials to GitHub Secrets
- Image doesn't exist for your platform (amd64 vs arm64) → check image manifest
- Rate limiting from Docker Hub → authenticate Trivy with Docker Hub token

**Fix**: Update `.github/workflows/container-security-scan.yml` with credentials:
```yaml
- name: Run Trivy vulnerability scanner
  env:
    DOCKER_USERNAME: ${{ secrets.DOCKER_USERNAME }}
    DOCKER_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}
```

### False Positive Vulnerabilities

If Trivy reports vulnerabilities that don't apply:

1. **Check if you use the affected component**: Many images bundle software you don't actually run
2. **Suppress specific CVEs** in `.trivyignore`:
   ```
   # Suppress CVE-2024-1234 (explain why)
   CVE-2024-1234
   ```
3. **Document your decision** in the PR comments for future reference

### Renovate Creating Too Many PRs

**Adjust update frequency** in `renovate.json`:
```json
{
  "schedule": ["on the 1st day of the month"]  // Change to quarterly, etc.
}
```

**Group related updates**:
```json
{
  "groupName": "non-critical-containers",
  "matchPackageNames": ["docker.io/amir20/dozzle", "..."]
}
```

## Maintenance Tasks

### Monthly (Automated by Renovate)
- Review update PRs within 48 hours (security) or 1 week (routine)
- Test on `rvn-srv` before merging
- Check Trivy scan results

### Quarterly (Manual)
- Review excluded local images (`helium`, `openmemory`)
- Check upstream repos for security advisories
- Audit `renovate.json` for stale configurations

### Annually (Manual)
- Review critical services policy (still appropriate?)
- Consider upgrading to Tier 3 security (staging environment, automated testing)
- Audit Trivy suppression list (`.trivyignore`)

## Future Enhancements

**Potential improvements** (not currently implemented):

1. **Automated testing on `rvn-vm`** before `rvn-srv`:
   - Spin up a VM clone
   - Run health checks
   - Auto-merge if tests pass

2. **Dependency pinning with hash verification**:
   - Use Nix's `dockerTools.pullImage` with SHA256 hashes
   - Prevents supply chain attacks (image substitution)

3. **SBOM generation**:
   - Generate Software Bill of Materials for compliance
   - Track dependencies across all containers

4. **Slack/Discord notifications**:
   - Alert on CRITICAL security updates
   - Daily digest of pending PRs

5. **Auto-merge for low-risk updates**:
   - Patch version bumps auto-merge after Trivy passes
   - Reduces manual review burden

## References

- [Renovate Documentation](https://docs.renovatebot.com/)
- [Trivy Documentation](https://aquasecurity.github.io/trivy/)
- [Podman Quadlet](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [NixOS Container Options](https://search.nixos.org/options?query=virtualisation.oci-containers)
