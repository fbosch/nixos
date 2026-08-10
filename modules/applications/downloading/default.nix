{ config, ... }:
{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        media-downloader
        megasync
        p7zip
        speedtest-cli
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    let
      proxyHost = config.flake.meta.hosts.rvn-srv;
    in
    {
      xdg.dataFile."media-downloader/settings/settings.ini".text = ''
        [General]
        ThemeName=Dark
        ProxySettingsType=Manual
        ProxySettingsCustomSource=http://${proxyHost.local}:8889
      '';
    };
}
