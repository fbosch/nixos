{
  flake.modules.nixos.vpn = { pkgs, ... }: {
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
      protonvpn-gui
    ];
  };
}
