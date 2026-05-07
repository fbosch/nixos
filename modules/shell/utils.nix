{
  flake.modules.nixos.shell =
    { pkgs, ... }:
    let
      open = pkgs.writeShellScriptBin "open" ''
        exec ${pkgs.xdg-utils}/bin/xdg-open "$@"
      '';
    in
    {
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
  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      programs.fzf.enable = true;
      home.packages = with pkgs; [
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
}
