{ pkgs, lib, ... }:
let
  packages = with pkgs; {
    editors = [ vim neovim ];

    development = [ nodejs fnm git clang cargo rustc zig gcc cmake gnumake ];

    utilities = [
      wget
      curl
      ripgrep
      jq
      fd
      tree
      unzip
      uutils-coreutils
      killall
      nixfmt-rfc-style
    ];

    system = [ gparted polkit polkit_gnome parted ];
  };
in { environment.systemPackages = lib.flatten (lib.attrValues packages); }
