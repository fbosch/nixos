{ inputs, ... }:
{
  flake.modules.homeManager.applications =
    { pkgs, lib, ... }:
    {
      home.packages =
        with pkgs; [
          gimp
          pkgs.local.chromium-chatgpt
          pkgs.local.chromium-notion
          pkgs.local.chromium-protonmail
          pkgs.local.chromium-protoncalendar
          pkgs.local.chromium-linear
          pkgs.local.chromium-figma
        ];

      services.flatpak.packages = [
        "md.obsidian.Obsidian"
        "io.github.efogdev.mpris-timer"
      ];
    };
}
