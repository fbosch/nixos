{
  flake.modules.nixos.vpn = { pkgs, lib, ... }: {
    services = {
      startupPolicy.applications.vpn = {
        tier = lib.mkDefault "essential";
        units = [
          {
            name = "tailscaled.service";
            provider = "nixos";
          }
        ];
      };

      mullvad-vpn = {
        enable = true;
        package = pkgs.mullvad-vpn;
      };

      tailscale = {
        enable = true;
        useRoutingFeatures = "client";
      };
    };

    environment.systemPackages = with pkgs; [
      tailscale
      proton-vpn
    ];
  };
}
