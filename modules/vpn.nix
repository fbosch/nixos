{
  flake.modules.nixos.vpn =
    { pkgs, ... }:
    let
      mullvadExcludeIfConnected = pkgs.writeShellApplication {
        name = "mullvad-exclude-if-connected";
        text = ''
          if ${pkgs.mullvad-vpn}/bin/mullvad status 2>/dev/null | ${pkgs.gnugrep}/bin/grep -qx "Connected"; then
            exec ${pkgs.mullvad-vpn}/bin/mullvad-exclude "$@"
          fi

          exec "$@"
        '';
      };
    in
    {
      services.mullvad-vpn = {
        enable = true;
        package = pkgs.mullvad-vpn;
      };

      services.tailscale = {
        enable = true;
        useRoutingFeatures = "client";
      };

      environment.systemPackages = with pkgs; [
        tailscale
        proton-vpn
        mullvadExcludeIfConnected
      ];
    };
}
