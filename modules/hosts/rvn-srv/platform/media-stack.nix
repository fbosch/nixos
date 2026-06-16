_: {
  flake.modules.nixos."hosts/rvn-srv/platform" = {
    services = {
      plex.nginx.port = 32402;

      linkwarden-container = {
        port = 3100;
        nextauthUrl = "https://linkwarden.corvus-corax.synology.me";
        disableRegistration = true; # Set to true after first user registration
        cpus = "2.0";
        memory = "4g";
        memoryReservation = "2g";
        shmSize = "256m"; # Important for PDF/screenshot generation
        meilisearch.memory = "1g"; # Meilisearch was hitting OOM at 512m.
      };

      rdtclient = {
        port = 6500;
        downloadPath = "/mnt/nas/downloads";
        tempDownloadPath = "/mnt/nas/downloads/rdtclient-temp";
        timezone = "Europe/Copenhagen";
        userId = 1000;
        groupId = 1000;
        cpus = "0.25";
        memory = "4g";
      };
    };
  };
}
