{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        (nemo-with-extensions.override {
          extensions = [ local.nemo-image-converter ];
        })

        zip
        p7zip
        unrar
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, config, ... }:
    {
      home.sessionVariables = {
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop:${pkgs.nemo-with-extensions}/share/gsettings-schemas";
      };
    };
}
