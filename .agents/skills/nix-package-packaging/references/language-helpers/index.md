# Language-Specific Package Helpers

Sources:
- https://wiki.nixos.org/wiki/Language-specific_package_helpers
- https://nixos.org/nixpkgs/manual/#chap-language-support

Use this guide to decide when native nixpkgs builders are enough and when helper generators are justified.

## Decision Matrix (Native Builder First)

| Ecosystem | Native-first path | Escalate to helpers when | Notes |
|---|---|---|---|
| Go | `buildGoModule` | dependency graph export or non-standard module handling is required | `buildGoPackage` was removed in nixpkgs 25.05; avoid legacy patterns for new work |
| Rust | `rustPlatform.buildRustPackage` with `cargoHash` | you need generated crate graphs, custom incremental build topology, or workspace-heavy CI optimization | helpers (`naersk`, `crane`, `crate2nix`, `cargo2nix`) differ mainly in generation/incrementality trade-offs |
| Python | `buildPythonPackage` / `buildPythonApplication` | upstream workflow depends on `uv`/Poetry lock translation and native packaging is too costly | for new Poetry workflows, verify whether `uv` + `uv2nix` is preferable |
| JavaScript/Node | `buildNpmPackage` or Yarn hooks (`yarnConfigHook` etc.) | lockfile/tooling needs generated expressions or project-specific plugin workflow | `yarn2nix` functions are deprecated in nixpkgs manual guidance |
| Ruby | `bundlerApp` / `bundlerEnv` / `ruby.withPackages` | you need gemset generation from Bundler metadata | `bundix` is the common gemset generator |
| Haskell | `haskellPackages.mkDerivation` | Cabal metadata conversion and generated expression flow are needed | generated expressions should be consumed via `haskellPackages.callPackage` |
| Zig | `zig.hook` | unusual dependency transformation requires external generation | keep `zig.hook` as default path |

## Evidence-Based Escalation Triggers

Escalate from native builder to helper only when at least two signals are true.

| Ecosystem | Escalate when logs/repo evidence show | Preferred helper direction |
|---|---|---|
| Go | repeated module graph/vendor mismatch after normal `buildGoModule` fixes, or repo workflow depends on generated module manifests | `gomod2nix` |
| Rust | standard `buildRustPackage` flow is valid but CI/rebuild cost requires per-crate or incremental composition, or repo policy requires generated Cargo expression graph | `crane`, `crate2nix`, `cargo2nix`, `naersk` based on workflow |
| Python | native `buildPython*` route requires large manual lock translation from `uv`/Poetry metadata and this repeats across updates | `uv2nix` first, `poetry2nix` only when already adopted |
| JavaScript/Node | lockfile/package-manager model does not map cleanly to native path (especially Yarn v3/v4 workflows) and generated expressions are part of project workflow | `yarn-plugin-nixify`, `node2nix`, `napalm` |
| Ruby | Bundler graph maintenance becomes manual and error-prone without generated gemset updates | `bundix` |
| Haskell | manual Cabal dependency expression maintenance dominates changes and generated metadata improves reviewability | `cabal2nix` |
| Zig | `build.zig.zon` dependency graph needs explicit Nix representation for repeatable updates | `zon2nix` |

If only one signal appears, keep native builder and continue debugging in-place.

## Cross-Ecosystem Decision Tree

Use this before adopting any helper:

1. Can a native builder consume the existing lock/build metadata? If yes, stay native.
2. Did native path fail for at least two independent, repeated signals from logs? If no, keep debugging native path.
3. Does a helper reduce repeated maintenance work (not just one-off setup)? If no, avoid helper.
4. After adopting helper, are generated diffs reviewable and stable across updates? If no, roll back to native or narrower helper scope.

Exit criteria:
- Escalate only when steps 2 and 3 are both true.
- De-escalate when step 4 fails twice in consecutive updates.

## Helper Status Policy

- Treat helper status labels as documentation snapshots.
- When status materially affects recommendation, verify upstream before choosing a tool.
- Keep legacy helpers visible for migration and maintenance scenarios.

## Language References

- [Elisp](elisp.md)
- [Erlang](erlang.md)
- [Go](go.md)
- [Haskell](haskell.md)
- [JavaScript and Node.js](javascript-nodejs.md)
- [Lua](lua.md)
- [OCaml](ocaml.md)
- [Perl](perl.md)
- [PureScript](purescript.md)
- [Python](python.md)
- [Ruby](ruby.md)
- [Rust](rust.md)
- [Scala](scala.md)
- [Zig](zig.md)
