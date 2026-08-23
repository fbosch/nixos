{ inputs
, buildGoModule
, callPackage
,
}:

let
  version = "0.12.0";
  buildGoModuleWithReleaseFixes =
    attrs:
    buildGoModule (
      attrs
      // {
        vendorHash = "sha256-5iS75LoN9FC57XRAbIU+Pia1gcXyeiF7bqF3pndYXwM=";
        postPatch = (attrs.postPatch or "") + ''
          rm -rf vendor
        '';
        ldflags = [
          "-s"
          "-w"
          "-X main.version=${version}"
        ];
      }
    );
in
callPackage "${inputs.surge}/package.nix" {
  src = inputs.surge;
  inherit version;
  buildGoModule = buildGoModuleWithReleaseFixes;
}
