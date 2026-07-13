{
  flake.modules.homeManager.development =
    { pkgs, ... }:
    let
      inherit (pkgs) lib;

      optionalLocalPackages =
        names:
        lib.pipe names [
          (builtins.filter (name: lib.hasAttr name pkgs.local))
          (builtins.map (name: pkgs.local.${name}))
        ];

    in
    {
      config = {
        home.packages =
          (with pkgs; [
            codex
            # cursor-cli
            # aichat
            tesseract
          ])
          ++ optionalLocalPackages [
            "headroom"
            "no-mistakes"
            "plannotator"
            "pxpipe"
            "codexbar"
            "rtk"
          ];
      };
    };
}
