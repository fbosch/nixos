{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      programs.firejail.wrappedBinaries.vlc = {
        executable = "${pkgs.vlc}/bin/vlc";
        profile = "${pkgs.firejail}/etc/firejail/vlc.profile";
        desktop = "${pkgs.vlc}/share/applications/vlc.desktop";
      };
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.vlc ];
    };
}
