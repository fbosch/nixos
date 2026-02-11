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

  flake.modules.homeManager."virtualization/podman" =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        podman
        podman-compose
        podman-tui
      ];

      # Enable user-level podman socket for rootless containers
      # This properly manages the symlink to podman's systemd units
      systemd.user.sockets.podman = {
        Unit = {
          Description = "Podman API Socket";
          Documentation = "man:podman-system-service(1)";
        };
        Socket = {
          ListenStream = "%t/podman/podman.sock";
          SocketMode = "0660";
        };
        Install = {
          WantedBy = [ "sockets.target" ];
        };
      };
    };
}
