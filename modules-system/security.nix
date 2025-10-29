_: {
  services.getty.autologinUser = "fbb";
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.hyrpland.enableGnomeKeyring = true;

  security.sudo.extraConfig = ''
    Defaults lecture = never
    Defaults pwfeedback # password input feedback
    Defaults timestamp_timeout = 120 #  only ask for a password every 2 hours
  '';
}
