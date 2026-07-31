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
    };
}
