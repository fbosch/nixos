{
  flake.modules = {
    nixos.security =
      { pkgs, ... }:
      {
        services.gnome.gnome-keyring.enable = true;

        security = {
          # Use sudo-rs instead of traditional sudo (memory-safe Rust implementation)
          sudo-rs = {
            enable = true;
            extraConfig = ''
              Defaults !lecture
              Defaults pwfeedback
            '';
          };

          # Enable polkit for authentication dialogs (required for passkeys)
          polkit.enable = true;
        };

        # Enable U2F/FIDO2 support for passkeys
        # This allows FIDO2 security keys and platform authenticators to work
        services.udev.packages = [ pkgs.libfido2 ];

        # Install polkit agent for graphical sessions (required for authentication dialogs and passkeys)
        systemd.user.services.polkit-gnome-authentication-agent-1 = {
          description = "polkit-gnome-authentication-agent-1";
          wantedBy = [ "graphical-session.target" ];
          wants = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
            Restart = "on-failure";
            RestartSec = 1;
            TimeoutStopSec = 10;
          };
        };
      };

    darwin.security =
      { pkgs, ... }:
      {
        # Configure sudo with pwfeedback on Darwin
        security.sudo.extraConfig = ''
          Defaults !lecture
          Defaults pwfeedback
        '';
      };

    homeManager.security =
      { pkgs, ... }:
      {
        programs.gpg.enable = true;

        services.gpg-agent = {
          enable = true;
          pinentry.package = pkgs.pinentry-curses;
          enableSshSupport = true;
        };

        # Security tools
        home.packages = with pkgs; [ bitwarden-cli ];

        # Note: Bitwarden CLI data.json is NOT managed by Home Manager
        # to allow the CLI to write session data. Server URL should be
        # configured manually or via bootstrap scripts.
      };
  };
}
