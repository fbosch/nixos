{ ... }:
{
  services.getty.autologinUser = "fbb";
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.hyrpland.enableGnomeKeyring = true;
}
