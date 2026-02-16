{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  config.flake.modules.homeManager.shell =
    { config
    , lib
    , pkgs
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
          ServerAliveInterval = "30";
          ServerAliveCountMax = "3";
          TCPKeepAlive = "yes";
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

      privateKeyPath = config.sops.secrets.ssh-private-key.path;
      publicKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
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
                ServerAliveInterval = "30";
                ServerAliveCountMax = "3";
                TCPKeepAlive = "yes";
              };
            };
          }
        ];
      };

      home.file.".ssh/authorized_keys" = {
        text = lib.concatStringsSep "\n" allAuthorizedKeys;
      };

      home.activation.syncSshPublicKey = lib.hm.dag.entryAfter [ "sopsInstallSecrets" "writeBoundary" ] ''
        if [ -r ${privateKeyPath} ]; then
          $DRY_RUN_CMD ${lib.getExe' pkgs.coreutils "mkdir"} -p ${config.home.homeDirectory}/.ssh

          generated_pub="$(${lib.getExe' pkgs.openssh "ssh-keygen"} -y -f ${privateKeyPath})"
          current_pub=""

          if [ -r ${publicKeyPath} ]; then
            current_pub="$(${lib.getExe' pkgs.coreutils "cat"} ${publicKeyPath})"
          fi

          if [ "$generated_pub" != "$current_pub" ]; then
            $DRY_RUN_CMD ${lib.getExe' pkgs.bash "bash"} -c 'printf "%s\n" "$1" > "$2"' _ "$generated_pub" ${publicKeyPath}
            $DRY_RUN_CMD ${lib.getExe' pkgs.coreutils "chmod"} 644 ${publicKeyPath}
          fi
        fi
      '';

      # Enable and start ssh-agent
      services.ssh-agent.enable = true;
    };
}
