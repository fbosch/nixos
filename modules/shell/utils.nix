{
  flake.modules.nixos.shell =
    { pkgs, ... }:
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
        superfile
        zoxide
        broot
        skim
        mprocs
        tmux
        gum
        peco
        tree
        tldr
        grc
        cloc
        xh
        lynx
        jq
        yq
        fd
        hyperfine
        html2text
      ];
    };
}
