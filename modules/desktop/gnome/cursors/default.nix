{
  flake.modules.nixos.desktop =
    { lib, pkgs, ... }:
    let
      visionCursor = pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
        pname = "vision-cursor";
        version = "1.0";

        srcs = [
          (pkgs.fetchurl {
            url = "https://github.com/zDyant/Vision-Cursor/releases/download/v${finalAttrs.version}/Vision-Black-Linux.tar.gz";
            hash = "sha256-Mgz00DxJ4g6JCu5D1V/O507pJN9iEGw37SzFHAc9tVY=";
          })
          (pkgs.fetchurl {
            url = "https://github.com/zDyant/Vision-Cursor/releases/download/v${finalAttrs.version}/Vision-White-Linux.tar.gz";
            hash = "sha256-IYwWAyiNjosGxC5vddvnfGwtVghWOoCl0hXqxVsKDh4=";
          })
        ];

        sourceRoot = ".";
        dontBuild = true;

        installPhase = ''
          runHook preInstall

          mkdir -p $out/share/icons
          cp -R Vision-Black Vision-White $out/share/icons/

          runHook postInstall
        '';

        meta = {
          description = "Clean cursor inspired by Windows 11 style";
          homepage = "https://github.com/zDyant/Vision-Cursor";
          license = lib.licenses.cc-by-nc-nd-40;
        };
      });
    in
    {
      environment.systemPackages = [ visionCursor ];
    };
}
