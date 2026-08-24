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
  pname = "waybar-pointer";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = [
    pkgs.cmake
    pkgs.pkg-config
  ];

  buildInputs = hyprland.buildInputs ++ [ hyprland ];

  installPhase = ''
    runHook preInstall
    install -Dm755 libwaybar-pointer.so $out/lib/libwaybar-pointer.so
    runHook postInstall
  '';

  meta = {
    description = "Native bottom-edge pointer zones for a Hyprland Waybar controller";
    license = pkgs.lib.licenses.mit;
    maintainers = [ ];
    platforms = [ "x86_64-linux" ];
  };
}
