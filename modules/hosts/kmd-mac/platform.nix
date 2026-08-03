{
  flake.modules.darwin."hosts/kmd-mac/platform" =
    { pkgs, hostMeta, ... }:
    {
      system = {
        stateVersion = 5;
        inherit (hostMeta) primaryUser;
        keyboard = {
          enableKeyMapping = true;
          remapCapsLockToControl = true;
        };
      };

      nix = {
        # Let macOS throttle Nix CPU and I/O activity behind interactive work.
        daemonProcessType = "Background";

        settings = {
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
        variables.NH_FLAKE = "/Users/${hostMeta.primaryUser}/nixos";
        shells = [ pkgs.fish ];
      };
    };
}
