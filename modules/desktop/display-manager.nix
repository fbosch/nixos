_: {
  flake.modules.nixos.desktop =
    {
      pkgs,
      lib,
      config,
      meta,
      hostConfig ? { },
      ...
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

      username = meta.user.username;

      # Weston configuration for SDDM with custom monitor
      westonIni =
        let
          xcfg = config.services.xserver;
          baseConfig = {
            libinput = {
              enable-tap = config.services.libinput.mouse.tapping;
              left-handed = config.services.libinput.mouse.leftHanded;
            };
            keyboard = {
              keymap_model = xcfg.xkb.model;
              keymap_layout = xcfg.xkb.layout;
              keymap_variant = xcfg.xkb.variant;
              keymap_options = xcfg.xkb.options;
            };
          };
          # Add output configuration if monitor is specified
          outputConfig = lib.optionalAttrs (hostConfig ? sddmMonitor) {
            "output:${hostConfig.sddmMonitor}" = {
              mode = "preferred";
            };
            core = {
              # Disable other outputs to force display on specified monitor
              require-input = false;
            };
          };
        in
        (pkgs.formats.ini { }).generate "weston-sddm.ini" (baseConfig // outputConfig);
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
      services.displayManager.sddm = lib.mkIf (displayManagerMode == "sddm") {
        enable = true;
        wayland.enable = true;
      };

      # Additional Xorg setup for multi-monitor configurations
      services.xserver.displayManager.setupCommands = lib.mkIf (
        displayManagerMode == "sddm" && hostConfig ? sddmSetupCommands
      ) hostConfig.sddmSetupCommands;

      # Greetd Configuration (tuigreet or autologin)
      services.greetd = lib.mkIf (displayManagerMode != "sddm") {
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
