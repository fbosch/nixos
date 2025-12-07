{ inputs, ... }:
{
  flake.modules.nixos.sops = { config, ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];

    sops = {
      defaultSopsFile = ../secrets/secrets.yaml;
      age.keyFile = "/var/lib/sops-nix/key.txt";

      secrets = {
        github-token = {
          mode = "0440";
          group = "wheel";
        };
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
