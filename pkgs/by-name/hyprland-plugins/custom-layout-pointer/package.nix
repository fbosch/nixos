{ inputs
, stdenv
,
}:

let
  pkgs = import inputs.hyprland.inputs.nixpkgs {
    inherit (stdenv.hostPlatform) system;
  };
  hyprland = inputs.hyprland.packages.${stdenv.hostPlatform.system}.hyprland;
in
pkgs.gcc16Stdenv.mkDerivation {
  pname = "custom-layout-pointer";
  version = "0.2.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];

  buildInputs = hyprland.buildInputs ++ [ hyprland ];

  installPhase = ''
    runHook preInstall
    install -Dm755 libcustom-layout-pointer.so $out/lib/libcustom-layout-pointer.so
    runHook postInstall
  '';

  meta = {
    description = "Native pointer-driven drag resize for custom Hyprland Lua layouts";
    license = pkgs.lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
