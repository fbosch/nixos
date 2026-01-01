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
        eza
        lf
        yazi
        mprocs
        gum
      ];
    };
}
