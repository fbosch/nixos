{ config, pkgs, lib, inputs, ... }:

{
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    enableSshSupport = true;
  };
}
