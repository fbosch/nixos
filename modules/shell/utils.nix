{
  flake.modules.nixos.shell =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        wget
        curl
        ripgrep
        jq
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
        # Directory navigation & file management
        eza
        lf
        yazi
        zoxide
        broot
        skim

        # Process/task management
        mprocs
        tmux

        # Utilities
        gum
        peco
        tldr
        grc
        cloc

        # Network/HTTP
        xh
        lynx

        # System info
        hyperfine

        # Text processing
        html2text
      ];
    };
}
