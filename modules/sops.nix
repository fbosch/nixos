{ inputs, ... }: {
  flake.modules.homeManager.security = { pkgs, meta, ... }: {
    home.packages = with pkgs; [ sops ];
  };
  flake.modules.nixos.secrets = { config, meta, ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops = {
      defaultSopsFile = ../secrets/secrets.yaml;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets = {
        github-token = {
          mode = "0440";
          group = "wheel";
        };
        smb-username = {
          mode = "0400";
        };
        smb-password = {
          mode = "0400";
        };
      };

      # Generate .smbcredentials file from SOPS secrets
      templates."smbcredentials" = {
        content = ''
          username=${config.sops.placeholder.smb-username}
          password=${config.sops.placeholder.smb-password}
        '';
        mode = "0600";
        owner = meta.user.username;
      };
    };

    # Configure Nix to use GitHub token for API requests to prevent rate limiting
    # The token must be in format: access-tokens = github.com=TOKEN
    # This prevents rate limiting when fetching from GitHub
    nix.extraOptions = ''
      !include ${config.sops.secrets.github-token.path}
    '';
  };
}
