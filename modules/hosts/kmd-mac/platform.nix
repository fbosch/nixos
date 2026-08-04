{
  flake.modules.darwin."hosts/kmd-mac/platform" =
    { pkgs
    , lib
    , hostMeta
    , ...
    }:
    let
      userPath = lib.escapeShellArg "/Users/${hostMeta.primaryUser}";
    in
    {
      system = {
        stateVersion = 5;
        inherit (hostMeta) primaryUser;
        keyboard = {
          enableKeyMapping = true;
          remapCapsLockToControl = true;
        };
      };

      determinateNix = {
        enable = true;
        customSettings = {
          # Two small builds leave CPU and unified memory for macOS.
          max-jobs = 2;
          cores = 2;
        };
      };

      security.pam.services.sudo_local.touchIdAuth = true;

      environment = {
        systemPackages = with pkgs; [
          nh
          nix-output-monitor
          keychain
          neovim
          wezterm
          rectangle
        ];
        shells = [ pkgs.fish ];
      };

      system.activationScripts.postActivation.text = lib.mkAfter ''
        /usr/bin/dscl . -create ${userPath} UserShell /run/current-system/sw/bin/fish
      '';
    };
}
