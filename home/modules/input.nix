{ pkgs, lib, ... }: {
  dconf = {
    enable = true;
    settings = {
      "org/gnome/desktop/input-sources" = {
        sources = [
          (lib.hm.gvariant.mkTuple [ "xkb" "us" ])
          (lib.hm.gvariant.mkTuple [ "xkb" "dk" ])
        ];
      };
    };
  };
}

