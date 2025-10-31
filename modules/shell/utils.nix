{
  flake.modules.nixos.shell = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      wget
      curl
      ripgrep
      jq
      socat
      fd
      tree
      unzip
      uutils-coreutils
      killall
      nixfmt-rfc-style
      freshfetch
    ];
  };
  flake.modules.homeManager.shell = { pkgs, ... }: {
    home.packages = with pkgs; [
      eza
      lf
      yazi
    ];
  };
}
