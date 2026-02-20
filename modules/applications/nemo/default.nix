{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        (nemo-with-extensions.override {
          extensions = [ local.nemo-image-converter ];
        })

        # Archive tools (used by the extract-to-folder action)
        zip
        p7zip
        unrar
      ];
    };

  flake.modules.homeManager.applications =
    { pkgs, config, ... }:
    {
      home.sessionVariables = {
        # Nemo ships its GSettings schema under a versioned gsettings-schemas/
        # subdirectory that NixOS does not merge into the system profile.
        # Adding the store path to XDG_DATA_DIRS lets GLib find it so dconf
        # keys like thumbnail-limit are respected instead of using the 1 MB default.
        # Also includes ~/Desktop so files there appear in XDG data lookups.
        XDG_DATA_DIRS = "$XDG_DATA_DIRS:${config.home.homeDirectory}/Desktop:${pkgs.nemo-with-extensions}/share/gsettings-schemas";
      };
    };
}
