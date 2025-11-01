{ pkgs }:

pkgs.nix-webapps-lib.mkChromiumApp {
  appName = "chromium-youtubemusic";
  categories = [ "Network" "AudioVideo" "Audio" ];
  class = "chrome-music.youtube.com_-YoutubeMusicProfile";
  desktopName = "YouTube Music";
  icon = ./Youtube_Music_icon.svg;
  profile = "YoutubeMusicProfile";
  url = "https://music.youtube.com";
}
