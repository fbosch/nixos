{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      programs.firejail = {
        enable = true;
        wrappedBinaries.vlc = {
          executable = "${pkgs.vlc}/bin/vlc";
          profile = "${pkgs.firejail}/etc/firejail/vlc.profile";
          desktop = "${pkgs.vlc}/share/applications/vlc.desktop";
        };
      };
    };
}
