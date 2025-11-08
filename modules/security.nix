{
  flake.modules.nixos.security = _: {
    services.gnome.gnome-keyring.enable = true;

    security = {
      pam.services = {
        hyprland.enableGnomeKeyring = true;
        ly.enableGnomeKeyring = true;
      };

      sudo.extraConfig = ''
        Defaults lecture = never
        Defaults pwfeedback
      '';
    };
  };

  flake.modules.homeManager.security = { pkgs, ... }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      pinentry.package = pkgs.pinentry-curses;
      enableSshSupport = true;
    };
  };
}
