{ pkgs }:

let
  version = "1.0.59";
  src = pkgs.fetchzip {
    url = "https://github.com/Alocks/manga-scaler/releases/download/v${version}/manga-scaler.zip";
    hash = "sha256-G+Q56M8xeAkQ39QjTcScM8eu75JqmVkz+0BHvXOzXjg=";
    stripRoot = false;
  };
in
pkgs.runCommand "manga-scaler-${version}-onisaga"
{
  nativeBuildInputs = [ pkgs.patch ];
}
  ''
    mkdir -p "$out"
    cp -R ${src}/. "$out"
    chmod -R u+w "$out"
    patch --batch -d "$out" -p1 < ${./manga-scaler-onisaga.patch}
  ''
