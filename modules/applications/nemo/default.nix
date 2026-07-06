{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        (nemo-with-extensions.override {
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
