# proton-wow

`proton-wow` is a separately selectable Steam compatibility tool. It starts from the
GE-Proton11-7 x86_64 release and replaces only the VKD3D-Proton D3D12 DLLs.

## Provenance

- Base runner: [GE-Proton11-7](https://github.com/GloriousEggroll/proton-ge-custom/releases/tag/GE-Proton11-7), pinned to the release archive used by the package.
- VKD3D-Proton: upstream commit `af89350cc2eacd9da2293fbae96bd9ab4987c9bb`, the same submodule commit recorded by GE-Proton11-7.
- GE build patch: GE-Proton11-7's `0001-vkd3d-bound-present-waits-during-swapchain-drain.patch`, carried unchanged.
- Local diagnostic patch: a bounded `WARN` for the D3D12 `OPTIONS5` query and its ray-tracing tier. It uses the `PROTON-WOW VKD3D_OPTIONS5` prefix and does not enable DXR or change capability reporting.

The replacement is built for both `x86_64-windows` and `i386-windows` and installed
under `files/lib/wine/vkd3d-proton/`. The rest of the GE runner remains from the
pinned release archive. This package is instrumentation, not a ray-tracing fix.

The runner metadata uses the distinct name `proton-wow`. NixOS Steam receives its
`steamcompattool` output through `programs.steam.extraCompatPackages`; the Faugus
module exposes the same output at
`~/.local/share/Steam/compatibilitytools.d/proton-wow` for runner discovery.
