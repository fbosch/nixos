{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    let
      nemo = pkgs.nemo.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ pkgs.tinysparql ];
        mesonFlags = old.mesonFlags ++ [ "-Dtracker=true" ];
        patches = (old.patches or [ ]) ++ [ ./patches/vim-navigation.patch ];
        # Nemo's Tracker backend otherwise treats filename searches as case-sensitive.
        postPatch = (old.postPatch or "") + ''
          substituteInPlace libnemo-private/nemo-search-engine-tracker.c \
            --replace-fail \
            ' FILTER (contains(?fileName,' \
            ' FILTER (contains(lcase(?fileName), lcase('
          sed -i '0,/g_string_append (sparql, ")");/s//g_string_append (sparql, "))");/' libnemo-private/nemo-search-engine-tracker.c
        '';
        # NemoPreview uses an X11-only foreign-parent window API.
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/nemo --set GDK_BACKEND x11
        '';
      });
      rpgMakerImageDecrypter = pkgs.writeShellApplication {
        name = "rpg-maker-image-decrypter";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.local.rpgmasd
        ];
        text = builtins.readFile ./scripts/decrypt-rpg-maker-image.sh;
      };
      nemoPreview = pkgs.nemo-preview.overrideAttrs (old: {
        patches = (old.patches or [ ]) ++ [ ./patches/nemo-preview-image-converters.patch ];
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/js/viewers/image.js \
            --replace-fail '@BLP_CONV@' '${pkgs.local."blp-conv"}/bin/blp-conv' \
            --replace-fail '@RPG_MAKER_IMAGE_DECRYPTER@' '${rpgMakerImageDecrypter}/bin/rpg-maker-image-decrypter'
        '';
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        postFixup = (old.postFixup or "") + ''
          wrapProgram $out/bin/nemo-preview --set GDK_BACKEND x11
        '';
      });
    in
    {
      services.gnome.localsearch.enable = true;

      environment.systemPackages = with pkgs; [
        (nemo-with-extensions.override {
          inherit nemo;
          extensions = [
            local.nemo-image-converter
            pkgs.nemo-fileroller
            nemoPreview
          ];
        })

        file-roller
        zip
        p7zip
        unrar
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      xdg.configFile."gtk-3.0/gtk.css".source = ./css/gtk.css;
      xdg.configFile."gtk-3.0/nemo-transparency.css".source = ./css/nemo-transparency.css;

      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${pkgs.nemo-with-extensions}/share/gsettings-schemas";
      };
    };
}
