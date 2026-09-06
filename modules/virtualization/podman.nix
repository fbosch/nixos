{ config, ... }:
{
  flake.modules = {
    nixos."virtualization/podman" =
      { pkgs, ... }:
      {
        # Enable Podman
        virtualisation.podman = {
          enable = true;

          # Create a `docker` alias for podman, to use it as a drop-in replacement
          dockerCompat = true;

          # Required for containers under podman-compose to be able to talk to each other.
          defaultNetwork.settings.dns_enabled = true;

          # Prune stopped containers and dangling images without deleting tagged
          # images required by temporarily stopped Quadlet services.
          autoPrune = {
            enable = true;
            dates = "weekly";
          };

          # Enable Podman socket for docker-compatible API
          dockerSocket.enable = true;
        };

        # Keep a failed container start from repeatedly pulling an image until
        # the root filesystem is full.
        environment.etc."containers/systemd/container.d/10-restart-limit.conf".text = ''
          [Unit]
          StartLimitIntervalSec=1h
          StartLimitBurst=3

          [Service]
          RestartSec=60s
        '';

        # Add podman-compose for Docker Compose compatibility
        environment.systemPackages = with pkgs; [
          podman-compose
          podman-tui # TUI for managing pods, containers, and images
        ];

        # Add user to podman group for rootless containers
        users.users.${config.flake.meta.user.username}.extraGroups = [ "podman" ];

        # Ananicy rules for Podman container runtime
        services.ananicy.extraRules = [
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

    darwin."virtualization/podman" = { pkgs, ... }: {
      environment.systemPackages = with pkgs; [
        podman
        podman-compose
        podman-tui
      ];
    };

    homeManager."virtualization/podman" =
      { config
      , pkgs
      , lib
      , ...
      }:
      let
        inherit (pkgs.stdenv.hostPlatform) isDarwin;
        podmanMachineName = "podman-machine-default";
        startPodmanMachine = pkgs.writeShellScript "start-podman-machine" ''
          set -eu

          state="$(${pkgs.podman}/bin/podman machine inspect ${podmanMachineName} --format '{{.State}}' 2>/dev/null || true)"
          if [ "$state" != "running" ]; then
            ${pkgs.podman}/bin/podman machine start ${podmanMachineName}
          fi

          socket="$(${pkgs.podman}/bin/podman machine inspect ${podmanMachineName} --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
          if [ -z "$socket" ]; then
            printf '%s\n' "Podman machine socket is unavailable" >&2
            exit 1
          fi

          exec /bin/launchctl setenv DOCKER_HOST "unix://''${socket#unix://}"
        '';
      in
      {
        launchd.enable = lib.mkIf isDarwin true;

        # Enable user-level podman socket for rootless containers on Linux.
        # On macOS, Podman runs inside a VM and must be started via launchd.
        systemd.user.sockets.podman = lib.mkIf (!isDarwin) {
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

        launchd.agents.podman-machine = lib.mkIf isDarwin {
          enable = true;
          config = {
            ProgramArguments = [ "${startPodmanMachine}" ];
            RunAtLoad = true;
            StartInterval = 300;
            KeepAlive = false;
            StandardOutPath = "${config.home.homeDirectory}/Library/Logs/podman-machine.out.log";
            StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/podman-machine.err.log";
            EnvironmentVariables.PATH = lib.makeBinPath [ pkgs.podman ] + ":/usr/bin:/bin:/usr/sbin:/sbin";
          };
        };
      };
  };
}
