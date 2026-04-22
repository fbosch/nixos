{
  flake.modules.nixos."hosts/rvn-pc/fingerprint" =
    { pkgs, ... }:
    {
      environment.systemPackages = [
        pkgs.pam_u2f
      ];

      security.pam = {
        u2f = {
          enable = true;
          control = "sufficient";
          settings = {
            cue = true;
            interactive = true;
            appid = "pam://rvn-pc";
            origin = "pam://rvn-pc";
          };
        };

        services = {
          sudo.u2f.enable = true;
          hyprlock.u2f.enable = true;
        };
      };
    };
}
