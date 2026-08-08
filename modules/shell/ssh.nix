{ config, lib, ... }:
let
  flakeConfig = config;
in
{
  config.flake.modules.homeManager.shell =
    { config
    , lib
    , pkgs
    , hostMeta
    , ...
    }:
    let
      # Read host configurations from flake.meta.hosts
      hosts = flakeConfig.flake.meta.hosts or [ ];
      isCorporateHost = hostMeta.corporate or false;
      managedHosts = if isCorporateHost then [ ] else hosts;
      clientUseTailnet = hostMeta.useTailnet or false;
      # Helper function to get the appropriate address for a specific host
      getAddress =
        host:
        let
          address = if clientUseTailnet then host.tailscale else host.local;
        in
        if address == null || address == "" then null else address;
      hasSopsPrivateKey = lib.hasAttrByPath [ "sops" "secrets" "ssh-private-key" "path" ] config;
      privateKeyPath =
        if hasSopsPrivateKey then
          lib.getAttrFromPath [ "sops" "secrets" "ssh-private-key" "path" ] config
        else
          null;

      # Generate match blocks from host configurations
      mkMatchBlock =
        host:
        lib.mkMerge [
          {
            HostName = getAddress host;
            # Use host-specific user if defined, otherwise use default user
            User = host.user or flakeConfig.flake.meta.user.username;
            AddKeysToAgent = "yes";
            ServerAliveInterval = 30;
            ServerAliveCountMax = 3;
            TCPKeepAlive = "yes";
          }
          (lib.optionalAttrs hasSopsPrivateKey {
            IdentityFile = privateKeyPath;
          })
        ];

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

      publicKeyPath = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      sshAgent = hostMeta.sshAgent or "ssh-agent";
    in
    {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;

        settings = lib.mkMerge [
          (lib.mkMerge (map mkMatchBlocks managedHosts))
          {
            "ssh.dev.azure.com" = {
              IdentityFile = "~/.ssh/id_rsa";
              IdentitiesOnly = true;
              HostkeyAlgorithms = "+ssh-rsa";
              PubkeyAcceptedKeyTypes = "ssh-rsa";
              ServerAliveInterval = 30;
              ServerAliveCountMax = 3;
              TCPKeepAlive = "yes";
            };
          }
        ];
      };

      home.activation = lib.mkIf hasSopsPrivateKey {
        syncSshPublicKey = lib.hm.dag.entryAfter [ "sopsInstallSecrets" "writeBoundary" ] ''
          if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ]; then
            echo "Home Manager generation unchanged, skipping SSH public key sync"
          else
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
          fi
        '';
      };

      assertions = [
        {
          assertion = lib.elem sshAgent [
            "gpg"
            "ssh-agent"
          ];
          message = "hostMeta.sshAgent must be either gpg or ssh-agent";
        }
        {
          assertion = sshAgent != "gpg" || config.services.ssh-agent.enable == false;
          message = "GPG SSH support and Home Manager ssh-agent cannot both own the SSH agent socket.";
        }
      ];

      services.ssh-agent.enable = sshAgent == "ssh-agent";
    };
}
