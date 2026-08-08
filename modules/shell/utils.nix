{ config, ... }:
let
  inherit (config.flake.lib) lazyApp;
  sharedPackages =
    pkgs: with pkgs; [
      ripgrep
      eza
      lf
      yazi
      scooter
      zoxide
      broot
      skim
      mprocs
      tmux
      gum
      peco
      tree
      just
      grc
      (lazyApp pkgs cloc)
      xh
      lynx
      jq
      yq
      fd
      hyperfine
      html2text
      (lazyApp pkgs croc)
    ];
in
{
  flake.modules = {
    nixos.shell =
      { pkgs, ... }:
      let
        open = pkgs.writeShellScriptBin "open" ''
          exec ${pkgs.xdg-utils}/bin/xdg-open "$@"
        '';
      in
      {
        environment.systemPackages =
          (with pkgs; [
            wget
            curl
            socat
            xdg-utils
            unzip
            unrar
            p7zip
            killall
            nixfmt
            freshfetch
            open
          ])
          ++ sharedPackages pkgs;
      };

    darwin.shell = { pkgs, ... }: {
      environment.systemPackages = sharedPackages pkgs;
    };

    homeManager.shell = { pkgs, ... }: {
      programs.fzf.enable = true;
      home.packages = sharedPackages pkgs;
    };
  };
}
