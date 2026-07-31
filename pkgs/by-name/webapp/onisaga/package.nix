{ pkgs }:

let
  mangaScaler = import ./manga-scaler.nix { inherit pkgs; };
in
(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "onisaga";
  categories = [
    "Graphics"
    "Viewer"
  ];
  desktopName = "OniSaga";
  wmClass = "OniSaga";
  comment = "Read manga online";
  icon = ./onisaga.png;
  profile = "OniSagaProfile";
  url = "https://onisaga.com/home";
  rememberLastPage = true;
  runtime = {
    extraFlags = [
      "--hide-scrollbars"
      "--enable-unsafe-webgpu"
      "--use-vulkan=true"
      "--gr-context-type=gl"
      "--test-type=gpu"
    ];
    unpackedExtensions = [ mangaScaler ];
    waylandAppId = "onisaga";
  };
  keywords = [
    "manga"
    "manhwa"
    "manhua"
    "webapp"
    "helium"
  ];
}
