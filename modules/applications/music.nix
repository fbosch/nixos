{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [ local.chromium-youtubemusic ];
  };
}
