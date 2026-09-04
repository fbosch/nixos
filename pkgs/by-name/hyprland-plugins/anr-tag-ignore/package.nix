{
  inputs,
  stdenv,
}:

let
  pkgs = import inputs.hyprland.inputs.nixpkgs {
    inherit (stdenv.hostPlatform) system;
  };
  hyprland = inputs.hyprland.packages.${stdenv.hostPlatform.system}.hyprland;
in
pkgs.gcc16Stdenv.mkDerivation {
  pname = "anr-tag-ignore";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];

  buildInputs = hyprland.buildInputs ++ [ hyprland ];

  installPhase = ''
    runHook preInstall
    install -Dm755 libanr-tag-ignore.so $out/lib/libanr-tag-ignore.so
    runHook postInstall
  '';

  meta = {
    description = "Suppress Hyprland ANR state for windows carrying configured tags";
    license = pkgs.lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
