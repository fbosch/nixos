{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    enableSshSupport = true;
  };

  # services.xserver = {
  #   exportConfiguration = true;
  #   enablee = true;
  #   layout = "us,dk";
  #   xkbOptions = "eurosign:e, compose:menu, grp:alt_shift_toggle";
  # };

}
