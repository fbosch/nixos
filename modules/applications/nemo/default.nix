{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    let
      nemo = pkgs.nemo.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ pkgs.tinysparql ];
        mesonFlags = old.mesonFlags ++ [ "-Dtracker=true" ];
        # Nemo's Tracker backend otherwise treats filename searches as case-sensitive.
        postPatch = (old.postPatch or "") + ''
          substituteInPlace libnemo-private/nemo-search-engine-tracker.c \
            --replace-fail \
            ' FILTER (contains(?fileName,' \
            ' FILTER (contains(lcase(?fileName), lcase('
          sed -i '0,/g_string_append (sparql, ")");/s//g_string_append (sparql, "))");/' libnemo-private/nemo-search-engine-tracker.c
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
            pkgs.nemo-preview
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
      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${pkgs.nemo-with-extensions}/share/gsettings-schemas";
      };
    };
}
