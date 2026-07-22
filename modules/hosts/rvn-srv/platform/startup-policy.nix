{
  flake.modules.nixos."hosts/rvn-srv/platform" = {
    services.startupPolicy = {
      applications = {
        plex.tier = "standard";
        servarr.tier = "standard";
        rdtclient.tier = "standard";
        flaresolverr.tier = "standard";
        linkwarden.tier = "standard";
        openmemory.tier = "standard";
      };
    };
  };
}
