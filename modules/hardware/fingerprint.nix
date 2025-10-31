{
  flake.modules.nixos."hardware/fingerprint" = { pkgs, ... }: {
    services.fprintd.enable = true;

    security.pam.services = {
      login.fprintAuth = true;
      sudo.fprintAuth = true;
      gdm.fprintAuth = true;
      polkit-1.fprintAuth = true;
    };
  };
}
