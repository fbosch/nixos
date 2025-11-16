_:

{
  flake.overlays.proton-core-fix = _: prev:
    let
      inherit (prev) lib;
    in
    {
      python3Packages = prev.python3Packages.overrideScope' (_: pythonPrev:
        lib.optionalAttrs (pythonPrev ? proton-core) {
          proton-core = pythonPrev.proton-core.overridePythonAttrs (oldAttrs: {
            pytestCheckFlags = (oldAttrs.pytestCheckFlags or [ ]) ++ [
              "-k"
              "not test_compute_v and not test_generate_v and not test_srp"
            ];
          });
        }
      );
    };
}
