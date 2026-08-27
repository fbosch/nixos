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
  pname = "inset-border";
  version = "0.3.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];

  buildInputs = hyprland.buildInputs ++ [ hyprland ];

  installPhase = ''
    runHook preInstall
    install -Dm755 libinset-border.so $out/lib/libinset-border.so
    runHook postInstall
  '';

  meta = {
    description = "Configurable advanced-blend inset keylines for Hyprland windows";
    license = pkgs.lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
