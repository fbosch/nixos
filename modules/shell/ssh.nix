{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  config.flake.modules.homeManager.shell =
    { config
    , currentHostId ? null
    , ...
    }:
    let
      # Read host configurations from flake.meta.hosts
      hosts = flakeConfig.flake.meta.hosts or [ ];
      # Determine current host to choose Tailnet vs local addresses
      currentHostName = currentHostId;
      currentHost = lib.findFirst (host: host.name == currentHostName) null hosts;
      clientUseTailnet = currentHost != null && (currentHost.useTailnet or false);
      # Helper function to get the appropriate address for a specific host
      getAddress =
        host:
        let
          address = if clientUseTailnet then host.tailscale else host.local;
        in
        if address == null || address == "" then null else address;
      # Generate match blocks from host configurations
      mkMatchBlock = host: {
        hostname = getAddress host;
        # Use host-specific user if defined, otherwise use default user
        user = host.user or flakeConfig.flake.meta.user.username;
        identityFile = config.sops.secrets.ssh-private-key.path;
        extraOptions = {
          AddKeysToAgent = "yes";
        };
      };

      # Generate match blocks for both short key and full hostname
      mkMatchBlocks =
        host:
        let
          address = getAddress host;
          block = mkMatchBlock host;
        in
        lib.optionalAttrs (address != null) (
          lib.mkMerge [
            { ${host.name} = block; }
            (lib.optionalAttrs (host.sshAlias != null) { ${host.sshAlias} = block; })
          ]
        );

      # Collect all SSH public keys from hosts
      allAuthorizedKeys =
        flakeConfig.flake.meta.user.ssh.authorizedKeys
        ++ (lib.filter (key: key != null && key != "") (map (host: host.sshPublicKey) hosts));
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        matchBlocks = lib.mkMerge [
          (lib.mkMerge (map mkMatchBlocks hosts))
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
