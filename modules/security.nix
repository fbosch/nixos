{
  flake.modules.nixos.security = _: {
    services.gnome.gnome-keyring.enable = true;

    security = {
      pam.services = {
        hyprland.enableGnomeKeyring = true;
      };

      sudo.extraConfig = ''
        Defaults lecture = never
        Defaults pwfeedback
      '';
    };
  };

  flake.modules.homeManager.security = { pkgs, meta, ... }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      pinentry.package = pkgs.pinentry-curses;
      enableSshSupport = true;
    };

    # Bitwarden CLI
    home.packages = [ pkgs.bitwarden-cli ];

    # Configure Bitwarden server URL
    home.file.".config/Bitwarden CLI/data.json".text = builtins.toJSON {
      inherit (meta.bitwarden) serverUrl;
    };
  };
}
