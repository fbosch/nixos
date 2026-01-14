{
  flake.modules.nixos.shell =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wget
        curl
        socat
        xdg-utils
        fd
        tree
        unzip
        unrar
        p7zip
        killall
        nixfmt-rfc-style
        freshfetch
      ];
    };
  flake.modules.homeManager.shell =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        ripgrep
        eza
        lf
        yazi
        zoxide
        broot
        skim
        mprocs
        tmux
        gum
        peco
        tldr
        grc
        cloc
        xh
        lynx
        jq
        hyperfine
        html2text
      ];
    };
}
