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
      # Read host configurations from flake.meta.hosts
      hosts = flakeConfig.flake.meta.hosts or { };

      # Helper function to get the appropriate hostname
      getHostname = host:
        if flakeConfig.flake.ssh.useTailscale then host.tailscale else host.local;

      # Generate match blocks from host configurations
      mkMatchBlock = _name: host: {
        hostname = getHostname host;
        # Use host-specific user if defined, otherwise use default user
        user = host.user or flakeConfig.flake.meta.user.username;
        identityFile = config.sops.secrets.ssh-private-key.path;
      };

      # Collect all SSH public keys from hosts
      allAuthorizedKeys =
        flakeConfig.flake.meta.user.ssh.authorizedKeys
        ++ (lib.mapAttrsToList (_name: host: host.sshPublicKey) hosts);
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
        text = lib.concatStringsSep "\n" allAuthorizedKeys;
      };

      # Enable and start ssh-agent
      services.ssh-agent.enable = true;
    };
}
