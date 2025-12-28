{
  flake.modules.nixos.security = _: {
    services.gnome.gnome-keyring.enable = true;

    security = {
      pam.services = { hyprland.enableGnomeKeyring = true; };

      # Use sudo-rs instead of traditional sudo (memory-safe Rust implementation)
      sudo-rs = {
        enable = true;
        extraConfig = ''
          Defaults lecture = never
          Defaults pwfeedback
        '';
      };
    };
  };

  flake.modules.homeManager.security = { pkgs, ... }: {
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
}
