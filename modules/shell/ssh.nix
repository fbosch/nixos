{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  # Define flake-level option for SSH Tailscale preference
  options.flake.ssh = {
    useTailscale = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use Tailscale IPs for SSH hosts instead of local network IPs";
    };
  };

  config.flake.modules.homeManager.shell =
    { config, ... }:
    let
      # Define host configurations with both Tailscale and local IPs
      hosts = {
        pc = {
          tailscale = "100.124.57.90";
          local = "192.168.1.169";
          user = "fbb";
        };
        srv = {
          tailscale = "100.125.172.110";
          local = "192.168.1.46";
          user = "fbb";
        };
        mac = {
          tailscale = "100.118.36.81";
          local = "192.168.1.215";
          user = "fbb";
        };
      };

      # Helper function to get the appropriate hostname
      getHostname = host:
        if flakeConfig.flake.ssh.useTailscale then host.tailscale else host.local;

      # Generate match blocks from host configurations
      mkMatchBlock = _name: host: {
        hostname = getHostname host;
        inherit (host) user;
        identityFile = config.sops.secrets.ssh-private-key.path;
      };
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks = lib.mkMerge [
          (lib.mapAttrs mkMatchBlock hosts)
          {
            "ssh.dev.azure.com" = {
              identityFile = "~/.ssh/id_rsa.pub";
              identitiesOnly = true;
              extraOptions = {
                HostkeyAlgorithms = "+ssh-rsa";
                PubkeyAcceptedKeyTypes = "ssh-rsa";
              };
            };
          }
        ];
      };

      home.file.".ssh/authorized_keys" = {
        text = lib.concatStringsSep "\n" flakeConfig.flake.meta.user.ssh.authorizedKeys;
      };

      # Enable and start ssh-agent
      services.ssh-agent.enable = true;
    };
}
