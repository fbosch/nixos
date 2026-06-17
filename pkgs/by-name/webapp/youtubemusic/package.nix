{ pkgs }:

(import ../helium-webapps.nix { inherit pkgs; }).mkHeliumApp {
  appName = "youtubemusic";
  categories = [
    "Network"
    "AudioVideo"
    "Audio"
  ];
  desktopName = "YouTube Music";
  wmClass = "YouTube Music";
  comment = "Music streaming service";
  faviconHash = "sha256-ViRlq34tVujkLdRWZE3Bg5oLFBJ65dm+Tngq4wvtJYE=";
  profile = "YoutubeMusicProfile";
  profileDirName = "youtubemusic";
  url = "https://music.youtube.com";
  runtime = {
    extraFlags = [ "--hide-scrollbars" ];
    policyOverrides = {
      DefaultMediaStreamSetting = 1;
    };
  };
  keywords = [
    "music"
    "youtube"
    "webapp"
    "helium"
  ];
}
