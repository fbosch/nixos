{ config, ... }:
{
  flake.modules.nixos."virtualization/podman" =
    { pkgs, ... }:
    {
      # Enable Podman
      virtualisation.podman = {
        enable = true;

        # Create a `docker` alias for podman, to use it as a drop-in replacement
        dockerCompat = true;

        # Required for containers under podman-compose to be able to talk to each other.
        defaultNetwork.settings.dns_enabled = true;

        # Automatically prune old images and containers
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };

        # Enable Podman socket for docker-compatible API
        dockerSocket.enable = true;
      };

      # Add podman-compose for Docker Compose compatibility
      environment.systemPackages = with pkgs; [
        podman-compose
        podman-tui # TUI for managing pods, containers, and images
      ];

      # Add user to podman group for rootless containers
      users.users.${config.flake.meta.user.username}.extraGroups = [ "podman" ];

      # Enable user-level podman socket for rootless containers
      systemd.user.sockets.podman = {
        enable = true;
        wantedBy = [ "sockets.target" ];
      };

      # Ananicy rules for Podman container runtime
      services.ananicy.customRules = [
        {
          name = ".podman-wrapped";
          type = "Service";
          nice = 0;
        }
        {
          name = "conmon";
          type = "Service";
          nice = 0;
        }
      ];
    };
}
