{
  flake.modules.nixos.vpn =
    { pkgs, ... }:
    let
      mullvadExcludeIfConnected = pkgs.writeShellApplication {
        name = "mullvad-exclude-if-connected";
        text = ''
          connectivity="$(
            ${pkgs.coreutils}/bin/timeout 0.1s \
              ${pkgs.networkmanager}/bin/nmcli \
              --get-values CONNECTIVITY general 2>/dev/null || true
          )"

          if [ "$connectivity" = "full" ]; then
            exec /run/wrappers/bin/mullvad-exclude "$@"
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
