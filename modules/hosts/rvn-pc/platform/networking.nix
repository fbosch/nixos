{
  config,
  lib,
  ...
}:
let
  hostMeta = lib.findFirst (host: host.name == "rvn-pc") null config.flake.meta.hosts;
in
{
  flake.modules.nixos."hosts/rvn-pc/platform" = {
    assertions = [
      {
        assertion = hostMeta != null;
        message = "Missing host metadata for rvn-pc";
      }
    ];
    networking = {
      hostName = "rvn-pc";
      networkmanager.enable = true;
      nameservers = hostMeta.dnsServers;
      timeServers = [ "time.nist.gov" ];
    };

    services.tailscale.extraSetFlags = [ "--accept-dns=false" ];
  };
}
