{ inputs
, config
, lib
, ...
}:
let
  flakeConfig = config;
  user = flakeConfig.flake.meta.user.username;
  inherit (flakeConfig.flake.lib) sopsHelpers;

  # Secret file paths
  commonFile = ../secrets/common.yaml;
  apisFile = ../secrets/apis.yaml;

  # Permission presets
  inherit (sopsHelpers)
    rootOnly
    wheelReadable
    worldReadable
    ;
  userOwned = {
    mode = "0600";
    owner = user;
  };

  # Secret generators
  inherit (sopsHelpers)
    mkSecrets
    mkSecretsWithOpts
    mkSecret
    ;
in
{
  flake.modules = {
    homeManager = {
      security =
        { pkgs, ... }:
        {
          home.packages = with pkgs; [
            sops
            age
          ];
        };

      # Home Manager SOPS module - works on both NixOS and Darwin
      secrets =
        { config
        , lib
        , ...
        }:
        let
          hmConfig = config;
        in
        {
          imports = [ inputs.sops-nix.homeManagerModules.sops ];

          sops = {
            defaultSopsFile = commonFile;
            age.keyFile = "${hmConfig.home.homeDirectory}/.config/sops/age/keys.txt";
            age.generateKey = true;

            secrets = lib.mkMerge [
              # Common secrets (no special options needed for HM)
              (mkSecrets commonFile [
                "github-token"
                "smb-username"
                "smb-password"
              ])

              # API secrets
              (mkSecrets apisFile [
                "context7-api-key"
                "kagi-api-token"
                "openai-api-key"
              ])

              # Special cases with custom options
              {
                ssh-private-key = mkSecret commonFile {
                  path = "${hmConfig.home.homeDirectory}/.ssh/id_ed25519";
                };
              }
            ];
          };

        };
    };

    # NixOS-specific SOPS module (system-level secrets)
    nixos.secrets =
      { config
      , ...
      }:
      let
        nixosConfig = config;
      in
      {
        imports = [ inputs.sops-nix.nixosModules.sops ];

        sops = {
          defaultSopsFile = commonFile;
          age.keyFile = "/var/lib/sops-nix/key.txt";
          age.generateKey = true;

          secrets = lib.mkMerge [
            # Common secrets - wheel readable
            (mkSecretsWithOpts commonFile wheelReadable [
              "github-token"
            ])

            # API secrets - wheel readable
            (mkSecretsWithOpts apisFile wheelReadable [
              "kagi-api-token"
              "openai-api-key"
            ])

            # API secrets - world readable
            (mkSecretsWithOpts apisFile worldReadable [
              "context7-api-key"
            ])

            # Special cases
            {
              ssh-private-key = mkSecret commonFile userOwned;
            }
          ];

          templates = {
            "nix-github-token" = {
              content = ''
                access-tokens = github.com=${nixosConfig.sops.placeholder.github-token}
              '';
              mode = "0440";
              group = "wheel";
            };

          };
        };

        nix.extraOptions = ''
          !include ${nixosConfig.sops.templates."nix-github-token".path}
        '';
      };

    # Darwin-specific SOPS module (system-level secrets)
    darwin.secrets =
      { config
      , ...
      }:
      let
        darwinConfig = config;
      in
      {
        imports = [ inputs.sops-nix.darwinModules.sops ];

        sops = {
          defaultSopsFile = commonFile;
          age.keyFile = "/var/lib/sops-nix/key.txt";
          age.generateKey = true;

          secrets = lib.mkMerge [
            # Common secrets - root only
            (mkSecretsWithOpts commonFile rootOnly [
              "smb-username"
              "smb-password"
            ])

            # Common secrets - wheel readable
            (mkSecretsWithOpts commonFile wheelReadable [
              "github-token"
            ])

            # API secrets - wheel readable
            (mkSecretsWithOpts apisFile wheelReadable [
              "kagi-api-token"
              "openai-api-key"
              "wakapi-password-salt"
            ])

            # API secrets - world readable
            (mkSecretsWithOpts apisFile worldReadable [
              "context7-api-key"
            ])

            # Special cases
            {
              ssh-private-key = mkSecret commonFile userOwned;
            }
          ];

          templates = {
            "smbcredentials" = {
              content = ''
                username=${darwinConfig.sops.placeholder.smb-username}
                password=${darwinConfig.sops.placeholder.smb-password}
              '';
              mode = "0600";
              owner = user;
            };

            "nix-github-token" = {
              content = ''
                access-tokens = github.com=${darwinConfig.sops.placeholder.github-token}
              '';
              mode = "0440";
              group = "wheel";
            };
          };
        };

        nix.extraOptions = ''
          !include ${darwinConfig.sops.templates."nix-github-token".path}
        '';
      };
  };
}
