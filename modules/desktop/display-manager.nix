_: {
  flake.modules.nixos.desktop =
    { pkgs
    , lib
    , config
    , meta
    , hostConfig ? { }
    , ...
    }:
    let
      # Get display manager mode from hostConfig or use default
      displayManagerMode = hostConfig.displayManagerMode or meta.displayManager.defaultMode;

      # TUIGreet configuration
      tuigreetTheme = builtins.readFile ../../configs/greetd/theme.txt;
      nixosVersion = "${config.system.nixos.release} ${config.system.nixos.codeName}";
      issueText = builtins.readFile ../../configs/greetd/issue.txt;

      # Session script for greetd
      sessionScript = builtins.readFile ../../configs/greetd/session-hyprland.sh;

      inherit (meta.user) username;
    in
    {
      environment.etc = {
        "issue" = lib.mkIf (displayManagerMode == "tuigreet") {
          text = ''
            ${issueText}
            ${nixosVersion}
          '';
        };

        "greetd/session-hyprland" = lib.mkIf (displayManagerMode != "sddm") {
          text = sessionScript;
          mode = "0755";
        };
      };

      # SDDM Configuration
      services = {
        displayManager.sddm = lib.mkIf (displayManagerMode == "sddm") {
          enable = true;
          wayland.enable = true;
        };

        # Additional Xorg setup for multi-monitor configurations
        xserver.displayManager.setupCommands = lib.mkIf
          (
            displayManagerMode == "sddm" && hostConfig ? sddmSetupCommands
          )
          hostConfig.sddmSetupCommands;

        # Greetd Configuration (tuigreet or autologin)
        greetd = lib.mkIf (displayManagerMode != "sddm") {
          enable = true;
          settings = {
            default_session =
              if displayManagerMode == "tuigreet" then
                {
                  # TUIGreet: terminal-based greeter
                  command = ''
                    ${pkgs.tuigreet}/bin/tuigreet --time --remember --asterisks --issue --greet-align center --theme ${lib.escapeShellArg (lib.removeSuffix "\n" tuigreetTheme)} --sessions "" --cmd /etc/greetd/session-hyprland
                  '';
                  user = "greeter";
                }
              else
                {
                  # Legacy autologin mode (kept for compatibility)
                  command = "/etc/greetd/session-hyprland";
                  user = username;
                };
          };
        };
      };

      systemd.services.greetd = lib.mkIf (displayManagerMode != "sddm") {
        wantedBy = [ "graphical.target" ];
      };

      # Enable GNOME Keyring unlock via PAM
      security.pam.services = {
        greetd.enableGnomeKeyring = lib.mkIf (displayManagerMode != "sddm") true;
        sddm.enableGnomeKeyring = lib.mkIf (displayManagerMode == "sddm") true;
      };
    };
}
