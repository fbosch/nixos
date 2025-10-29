{
  flake.modules.nixos.security = {
    services.getty.autologinUser = "fbb";
    services.gnome.gnome-keyring.enable = true;
    security.pam.services.hyrpland.enableGnomeKeyring = true;

    security.sudo.extraConfig = ''
      Defaults lecture = never
      Defaults pwfeedback
      Defaults timestamp_timeout = 120
    '';
  };
}
