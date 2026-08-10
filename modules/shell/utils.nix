let
  sharedSystemPackages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
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
      cloc
      xh
      lynx
      jq
      yq
      fd
      hyperfine
      html2text
      croc
    ];
  };
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
        imports = [ sharedSystemPackages ];

        environment.systemPackages = with pkgs; [
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
        ];
      };

    darwin.shell = {
      imports = [ sharedSystemPackages ];
    };

    homeManager.shell = { pkgs, ... }: {
      programs.fzf.enable = true;
    };
  };
}
