{ config, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      (lazyDesktopApp pkgs {
        pkg = pkgs.vscodium;
        exe = "codium";
        desktopItem = {
          name = "codium";
          exec = "codium";
          desktopName = "VSCodium";
          genericName = "Code Editor";
          comment = "Free and open-source distribution of VS Code";
          icon = ./vscodium.png;
          terminal = false;
          categories = [
            "Development"
            "IDE"
            "TextEditor"
          ];
        };
      })
      gimp
      local."webapp/chatgpt"
      local."webapp/notion"
      local."webapp/icloud-notes"
      local."webapp/protonmail"
      local."webapp/protoncalendar"
      local."webapp/linear"
      local."webapp/figma"
      local."webapp/apple-maps"
    ];
  };

  flake.modules.homeManager.applications =
    { lib, ... }:
    {
      services.flatpak.packages = [
        "md.obsidian.Obsidian"
        "io.github.efogdev.mpris-timer"
        "io.github.tanaybhomia.Whisp"
      ];
    };
}
