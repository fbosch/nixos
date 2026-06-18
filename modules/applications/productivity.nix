{ inputs, ... }:
{
  flake.modules.homeManager.applications =
    { pkgs, lib, ... }:
    {
      home.packages = with pkgs; [
        gimp
        pkgs.local."webapp/chatgpt"
        pkgs.local."webapp/notion"
        pkgs.local."webapp/icloud-notes"
        pkgs.local."webapp/protonmail"
        pkgs.local."webapp/protoncalendar"
        pkgs.local."webapp/linear"
        pkgs.local."webapp/figma"
      ];

      services.flatpak.packages = [
        "md.obsidian.Obsidian"
        "io.github.efogdev.mpris-timer"
        "io.github.tanaybhomia.Whisp"
      ];
    };
}
