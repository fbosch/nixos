{ config, ... }:
let
  inherit (config.flake.lib) lazyDesktopApp;
in
{
  flake.modules.nixos.development = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      vim
      neovim
      (lazyDesktopApp pkgs {
        pkg = vscodium;
        exe = "codium";
        desktopItem = {
          name = "codium";
          exec = "codium";
          desktopName = "VSCodium";
          genericName = "Code Editor";
          comment = "Free and open-source distribution of VS Code";
          icon = ../../assets/icons/vscodium.svg;
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
}
