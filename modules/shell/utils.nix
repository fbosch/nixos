let
  sharedSystemPackages =
    { pkgs, ... }:
    let
      # Nixpkgs mprocs also ships an experimental dekit; only the pinned package should provide it.
      mprocsWithoutDekit = pkgs.symlinkJoin {
        name = "mprocs-without-dekit";
        paths = [ pkgs.mprocs ];
        postBuild = ''
          test -x "$out/bin/mprocs"
          rm "$out/bin/dekit"
          test ! -e "$out/bin/dekit"
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        ripgrep
        eza
        lf
        yazi
        scooter
        zoxide
        broot
        skim
        local.dekit
        mprocsWithoutDekit
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
