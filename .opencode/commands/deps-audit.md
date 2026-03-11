---
description: Audit custom package and container update pins using renovate-aligned rules
agent: plan
subtask: true
---

Audit this repo's self-managed dependencies with `renovate.json` as the primary classification model.

Args:

- `$1`: output mode. One of `report`, `compact`, `json`, `parity`, `updates`, `target`.
- `$2`: optional primary filter token.
- `$ARGUMENTS`: full trailing raw argument string.
- Default mode: `report`.

Behavior:

- Align your discovery logic to the regex managers and package rules in `@renovate.json`.
- Treat Renovate coverage as the baseline, then identify gaps, weak pins, local-build exceptions, and suspicious mismatches.
- Default to a structural offline audit. Only attempt live upstream version checks in `updates` mode, and only for high-confidence matches.
- Never modify files.

Mode handling:

- If `$1` is empty, use `report`.
- If `$1` is not one of `report`, `compact`, `json`, `parity`, `updates`, `target`, respond only with: `Usage: /deps-audit [report|compact|json|parity|updates|target <filter>] [filter]`
- In `target` mode, derive the filter from `$ARGUMENTS` with the leading `target` token removed. If that derived filter is empty, respond only with: `Usage: /deps-audit target <filter>`

Primary reference:
@renovate.json

Current package inventory:
!`rg --files pkgs/by-name -g 'package.nix' | sort`

Current container inventory:
!`rg --files modules/services/containers -g '*.nix' | sort`

Container image signals:
!`rg -n 'Image=|imageTag\s*=\s*lib\.mkOption|image\s*=\s*lib\.mkOption|redisImageTag\s*=\s*lib\.mkOption|default\s*=\s*"latest"|gitRev\s*=|openmemoryRev\s*=' modules/services/containers`

Package source signals:
!`rg -n 'version\s*=|fetchFromGitHub|fetchurl|fetchzip|mkChromiumApp|url\s*=\s*"https://github\.com/' pkgs/by-name/*/package.nix`

Task:

1. Build an inventory of update targets under `pkgs/by-name/` and `modules/services/containers/`.
2. For each target, classify:
   - `kind`: `container`, `package`, `webapp-wrapper`, or `local-build`
   - `extractionKind`: `hardcoded-image`, `image-option`, `imageTag-option`, `github-fetchurl`, `github-fetchFromGitHub`, `github-fetchzip`, `non-github-fetchurl`, `monorepo-subdir`, `manual`, or a better repo-accurate label if needed
   - `renovateCoverage`: `matched`, `disabled`, `unmatched`, or `ambiguous`
   - `pinQuality`: `exact`, `tag`, `latest`, `commit`, `pseudo-version`, or `mixed`
   - `riskGroup`: infer from Renovate package rules where possible
3. Flag notable issues such as:
   - `latest` tags
   - local-only images intentionally disabled in Renovate
   - declared version not matching embedded URL/rev
   - wrappers with no meaningful upstream artifact pin
   - multi-container modules with multiple independently updateable targets
4. In `updates` mode, check upstream latest versions only for high-confidence targets and clearly label confidence. Do not guess for weak/manual cases.

Output rules by mode:

`report`

- Return these sections in order:
  1. `Overview`
  2. `Actionable Updates`
  3. `Renovate Parity`
  4. `Manual Review`
  5. `Notable Edge Cases`
- Keep it concise but specific.

`compact`

- Return one line per target:
  `<target> | <kind> | <current pin> | <renovateCoverage> | <pinQuality> | <note>`

`json`

- Return valid JSON only.
- Shape:

```json
{
  "mode": "json",
  "summary": {
    "packages": 0,
    "containers": 0,
    "matched": 0,
    "disabled": 0,
    "unmatched": 0,
    "ambiguous": 0
  },
  "targets": [
    {
      "name": "",
      "path": "",
      "kind": "",
      "extractionKind": "",
      "currentValue": "",
      "depName": "",
      "renovateCoverage": "",
      "pinQuality": "",
      "riskGroup": "",
      "notes": []
    }
  ]
}
```

`parity`

- Focus only on whether repo targets align with `renovate.json`.
- Group findings into `Matched`, `Disabled by Design`, `Unmatched`, and `Ambiguous Regex Coverage`.

`updates`

- Same shape as `report`, but include `latest known` and `update type` for each high-confidence result.
- Separate confirmed results from low-confidence/manual cases.

`target`

- Only report entries matching the provided filter text across name, path, depName, or image.
- Derive the filter from `$ARGUMENTS` rather than assuming only one token.

Important repo-specific expectations:

- Treat Chromium app packages under `pkgs/by-name/chromium-*` as wrappers unless the file clearly pins a real upstream artifact.
- Treat `modules/services/containers/helium.nix` and `modules/services/containers/openmemory.nix` as local-build flows aligned with Renovate's disabled local-image rule.
- Treat modules like `linkwarden`, `komodo`, and `rsshub` as potentially multi-target because they may pin sidecars separately.
- Treat `pkgs/by-name/font-zenbones/package.nix` and `pkgs/by-name/nemo-image-converter/package.nix` as likely `ambiguous` unless you can prove a clean Renovate match.
- Call out mismatches between declared `version` and embedded release URL or rev when found.
- Prefer exact file references in findings.
