# JavaScript and Node.js Helpers

Sources:
- https://nixos.org/nixpkgs/manual/#chap-language-support
- https://wiki.nixos.org/wiki/Language-specific_package_helpers

## Native Builder First

- Prefer lockfile-aware native paths before external generators.
- For npm projects, prefer `buildNpmPackage`.
- For Yarn projects, prefer nixpkgs Yarn hooks (`yarnConfigHook`, `yarnBuildHook`, `yarnInstallHook`) and current Yarn tooling.

## Decision Table

| Scenario | Preferred path | Helper fallback |
|---|---|---|
| npm project with `package-lock.json` | `buildNpmPackage` | `node2nix` or `napalm` when generation is explicitly required |
| Yarn v3/v4 project | Yarn hooks and modern Yarn workflow | `yarn-plugin-nixify` for project-integrated generation |
| Legacy repo already built around generated expressions | preserve until migration | `node2nix`, historical `yarn2nix` variants |

## Helper Pointers

- npm lock translation: `node2nix`, `napalm`.
- Yarn v3/v4 project-integrated generation: `yarn-plugin-nixify`.
- Legacy migration only: `yarn2nix` variants, `bower2nix`.

## Practical Guidance

- Match tool choice to upstream lockfile and package-manager reality.
- `yarn2nix` functions are deprecated in nixpkgs manual guidance; avoid introducing new packages that depend on them.
- Verify helper maintenance status at upstream before selecting a helper for new packaging work.

## Example Implementation

```nix
{ buildNpmPackage, fetchFromGitHub }:
buildNpmPackage rec {
  pname = "my-node-app";
  version = "1.0.0";
  src = fetchFromGitHub {
    owner = "org";
    repo = "my-node-app";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  npmDepsHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
}
```

```bash
# node2nix workflow (generated files consumed by callPackage).
node2nix -l package-lock.json
```

```nix
{ pkgs }:
pkgs.callPackage ./default.nix { }
```
