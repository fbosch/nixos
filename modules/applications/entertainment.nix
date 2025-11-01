{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [ steam local.chromium-youtubemusic ];
  };
}
