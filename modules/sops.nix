{ inputs, ... }:
{
  flake.modules.homeManager.security =
    { pkgs, meta, ... }:
    {
      home.packages = with pkgs; [
        sops
        age
      ];
    };
  flake.modules.nixos.secrets =
    { config
    , lib
    , meta
    , pkgs
    , ...
    }:
    {
      imports = [ inputs.sops-nix.nixosModules.sops ];

      sops = {
        defaultSopsFile = ../secrets/secrets.yaml;
        age.keyFile = "/var/lib/sops-nix/key.txt";
        # This will generate a new key if the key specified above does not exist
        age.generateKey = true;

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
          context7-api-key = {
            mode = "0444";
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

        # Generate nix.conf snippet with GitHub token
        templates."nix-github-token" = {
          content = ''
            access-tokens = github.com=${config.sops.placeholder.github-token}
          '';
          mode = "0440";
          group = "wheel";
        };
      };

      # Configure Nix to use GitHub token for API requests to prevent rate limiting
      # This prevents rate limiting when fetching from GitHub
      # TEMPORARILY DISABLED: Token is expired/invalid - update token in secrets.yaml
      # nix.extraOptions = ''
      #   !include ${config.sops.templates."nix-github-token".path}
      # '';

      # Make Contexty API key available as system-wide environment variable
      environment.variables = {
        CONTEXT7_API_KEY = "$(cat ${config.sops.secrets.context7-api-key.path})";
      };
    };
}
