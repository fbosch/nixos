{
  flake.modules.nixos.security = {
    services.getty.autologinUser = "fbb";
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.hyprland.enableGnomeKeyring = true;

    security.sudo.extraConfig = ''
      Defaults lecture = never
      Defaults pwfeedback
      Defaults timestamp_timeout = 120
    '';
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
