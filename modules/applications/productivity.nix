{ config, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = [
      (lazyDesktopApp pkgs {
        pkg = pkgs.vscodium;
        exe = "codium";
        desktopItem = {
          name = "codium";
          exec = "codium";
          desktopName = "VSCodium";
          genericName = "Code Editor";
          comment = "Free and open-source distribution of VS Code";
          icon = ../../assets/icons/vscodium.png;
          terminal = false;
          categories = [
            "Development"
            "IDE"
            "TextEditor"
          ];
        };
      })
    ];
  };

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
        pkgs.local."webapp/apple-maps"
      ];

      services.flatpak.packages = [
        "md.obsidian.Obsidian"
        "io.github.efogdev.mpris-timer"
        "io.github.tanaybhomia.Whisp"
      ];
    };
}
