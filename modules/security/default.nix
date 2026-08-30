let
  systemPackages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      bitwarden-cli
      clamav
    ];
  };
in
{
  flake.modules = {
    nixos.security =
      { pkgs, ... }:
      {
        imports = [ systemPackages ];

        services = {
          udev.packages = [ pkgs.libfido2 ];
          clamav.updater.enable = true;
        };

        # libfido2's udev rules combine session-scoped uaccess with this group.
        # Keep the group empty rather than granting permanent device access.
        users.groups.plugdev = { };

        security = {
          sudo-rs = {
            enable = true;
            extraConfig = ''
              Defaults !lecture
              Defaults pwfeedback
              Defaults timestamp_timeout=15
            '';
          };
          polkit.enable = true;
        };
      };

    darwin.security = {
      imports = [ systemPackages ];

      # Configure sudo with pwfeedback on Darwin
      security.sudo.extraConfig = ''
        Defaults !lecture
        Defaults pwfeedback
        Defaults timestamp_timeout=15
      '';
    };

    homeManager.security =
      { pkgs, ... }:
      {
        programs.gpg.enable = true;

        services.gpg-agent = {
          enable = true;
          pinentry.package = pkgs.pinentry-curses;
          enableSshSupport = false;
        };

      };
  };
}
