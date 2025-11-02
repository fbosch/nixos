{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-youtubemusic";
  categories = [ "Network" "AudioVideo" "Audio" ];
  class = "chromium-youtubemusic";
  desktopName = "YouTube Music";
  comment = "Music streaming service";
  icon = ./Youtube_Music_icon.svg;
  profile = "YoutubeMusicProfile";
  url = "https://music.youtube.com";
}
