{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  config.flake.modules.homeManager.shell =
    { config, ... }:
    let
      # Read host configurations from flake.meta.hosts
      hosts = flakeConfig.flake.meta.hosts or { };
      # Helper function to get the appropriate hostname for a specific host
      getHostname = host: if host.useTailnet or false then host.tailscale else host.local;
      # Generate match blocks from host configurations
      mkMatchBlock = _name: host: {
        hostname = getHostname host;
        # Use host-specific user if defined, otherwise use default user
        user = host.user or flakeConfig.flake.meta.user.username;
        identityFile = config.sops.secrets.ssh-private-key.path;
      };

      # Generate match blocks for both short key and full hostname
      mkMatchBlocks =
        name: host:
        let
          block = mkMatchBlock name host;
        in
        {
          ${name} = block;
        }
        // lib.optionalAttrs (host.hostname != name) {
          ${host.hostname} = block;
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
          (lib.mkMerge (lib.mapAttrsToList mkMatchBlocks hosts))
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
