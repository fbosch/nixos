# SOPS Integration Guide

This guide covers how to integrate SOPS secrets into dendritic flake modules.

## Overview

SOPS (Secrets OPerationS) encrypts secrets using age or GPG keys. In the dendritic pattern, secrets are:
- Encrypted in `secrets/secrets.yaml`
- Defined in modules using `sops.secrets.<name>`
- Referenced via `config.sops.secrets.<name>.path`
- Decrypted at runtime by the SOPS module

## Prerequisites

1. SOPS module must be imported in host configuration
2. Age key must exist for the host: `/etc/ssh/ssh_host_ed25519_key`
3. `.sops.yaml` must include the host's public key
4. Secrets file must exist: `secrets/secrets.yaml`

## Basic Secret Usage

### 1. Define Secret in Module

```nix
_:
{
  flake.modules.nixos."services/myapp" =
    { config
    , lib
    , pkgs
    , ...
    }:
    let
      cfg = config.services.myapp;
      apiKeyFile = config.sops.secrets.myapp-api-key.path;
    in
    {
      options.services.myapp = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
      };

      config = lib.mkIf cfg.enable {
        # Define the secret
        sops.secrets.myapp-api-key = {
          mode = "0400";
          owner = cfg.user;
          group = cfg.group;
        };

        # Use the secret in service
        systemd.services.myapp = {
          serviceConfig = {
            EnvironmentFile = apiKeyFile;
          };
        };
      };
    };
}
```

### 2. Add Secret to secrets.yaml

```bash
# Edit secrets file
sops secrets/secrets.yaml

# Add secret:
myapp-api-key: "secret-value-here"
```

### 3. Verify Secret Access

```bash
# After rebuild, check secret was created
ls -la /run/secrets/myapp-api-key

# Verify permissions
stat /run/secrets/myapp-api-key
```

## Secret Configuration Options

### Basic Options

```nix
sops.secrets.my-secret = {
  # File permissions (octal)
  mode = "0400";  # Read-only for owner
  
  # Owner user (string or UID)
  owner = "myapp";
  
  # Owner group (string or GID)
  group = "myapp";
  
  # Restart services on secret change
  restartUnits = [ "myapp.service" ];
};
```

### Advanced Options

```nix
sops.secrets.my-secret = {
  # Custom secret file (default: secrets/secrets.yaml)
  sopsFile = ./custom-secrets.yaml;
  
  # Custom secret key (default: attribute name)
  key = "different-key-name";
  
  # Custom secret path (default: /run/secrets/<name>)
  path = "/custom/path/to/secret";
  
  # Format of secret file
  format = "yaml";  # yaml, json, binary, dotenv
};
```

## Common Patterns

### Pattern 1: Environment File

**Use when**: Service needs multiple secrets as environment variables

```nix
sops.secrets.myapp-env = {
  mode = "0400";
  owner = "myapp";
};

systemd.services.myapp = {
  serviceConfig = {
    EnvironmentFile = config.sops.secrets.myapp-env.path;
  };
};
```

**secrets.yaml**:
```yaml
myapp-env: |
  API_KEY=secret-key
  DB_PASSWORD=secret-pass
  SECRET_TOKEN=secret-token
```

### Pattern 2: Token File

**Use when**: Service reads token from file

```nix
let
  tokenFile = config.sops.secrets.myapp-token.path;
in {
  sops.secrets.myapp-token = {
    mode = "0400";
    owner = "root";
  };

  systemd.services.myapp = {
    script = ''
      TOKEN=$(cat ${tokenFile})
      ${pkgs.myapp}/bin/myapp --token "$TOKEN"
    '';
  };
}
```

### Pattern 3: Configuration File

**Use when**: Service needs entire config file with secrets

```nix
sops.secrets.myapp-config = {
  mode = "0400";
  owner = "myapp";
  format = "json";
};

systemd.services.myapp = {
  serviceConfig = {
    ExecStart = "${pkgs.myapp}/bin/myapp --config ${config.sops.secrets.myapp-config.path}";
  };
};
```

### Pattern 4: Multiple Secrets

**Use when**: Service needs several separate secrets

```nix
{
  sops.secrets = {
    myapp-db-password = {
      mode = "0400";
      owner = "myapp";
    };
    
    myapp-api-key = {
      mode = "0400";
      owner = "myapp";
    };
    
    myapp-signing-key = {
      mode = "0400";
      owner = "myapp";
    };
  };

  systemd.services.myapp = {
    script = ''
      ${pkgs.myapp}/bin/myapp \
        --db-password-file ${config.sops.secrets.myapp-db-password.path} \
        --api-key-file ${config.sops.secrets.myapp-api-key.path} \
        --signing-key-file ${config.sops.secrets.myapp-signing-key.path}
    '';
  };
}
```

### Pattern 5: User-Specific Secret (Home Manager)

**Use when**: User needs secret in Home Manager context

```nix
# In Home Manager module
{
  sops.secrets.user-github-token = {
    mode = "0400";
    owner = config.home.username;
  };

  programs.git = {
    enable = true;
    extraConfig = {
      github.token = "!cat ${config.sops.secrets.user-github-token.path}";
    };
  };
}
```

### Pattern 6: Conditional Secret

**Use when**: Secret only needed if feature is enabled

```nix
config = lib.mkIf cfg.enable {
  sops.secrets.myapp-token = lib.mkIf cfg.useToken {
    mode = "0400";
    owner = cfg.user;
  };

  systemd.services.myapp = {
    script = lib.optionalString cfg.useToken ''
      TOKEN=$(cat ${config.sops.secrets.myapp-token.path})
    '';
  };
};
```

## Secret Management Workflow

### Adding a New Secret

1. **Define in module** (as shown above)

2. **Add to secrets.yaml**:
```bash
sops secrets/secrets.yaml
# Add: myapp-token: "value"
```

3. **Rebuild system**:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

4. **Verify secret**:
```bash
ls -la /run/secrets/
```

### Updating a Secret

1. **Edit secrets.yaml**:
```bash
sops secrets/secrets.yaml
# Update the value
```

2. **Rebuild**:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

3. **Restart services** (if not using `restartUnits`):
```bash
sudo systemctl restart myapp.service
```

### Removing a Secret

1. **Remove from module**:
```nix
# Delete sops.secrets.myapp-token definition
```

2. **Remove from secrets.yaml**:
```bash
sops secrets/secrets.yaml
# Delete the key
```

3. **Rebuild**:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

## Security Best Practices

### File Permissions

```nix
# Most restrictive (only owner can read)
mode = "0400";

# Owner read/write (for files that change)
mode = "0600";

# Group readable (for shared services)
mode = "0440";
```

### Ownership

```nix
# Service user owns secret
owner = "myapp";
group = "myapp";

# Root owns, service reads via group
owner = "root";
group = "myapp";
mode = "0440";
```

### Service Restart

```nix
# Auto-restart service on secret change
sops.secrets.myapp-token = {
  restartUnits = [ "myapp.service" ];
};
```

### Separate Secret Files

```nix
# Per-host secrets
sops.secrets.myapp-token = {
  sopsFile = ./secrets/host-specific.yaml;
};

# Per-service secrets
sops.secrets.myapp-token = {
  sopsFile = ./secrets/myapp.yaml;
};
```

## Common Issues

### Issue: Secret not found

**Symptom**: `/run/secrets/my-secret` doesn't exist

**Solutions**:
1. Check secret is defined in `secrets/secrets.yaml`
2. Verify `.sops.yaml` includes host's public key
3. Ensure SOPS module is imported in host config
4. Check for typos in secret name

### Issue: Permission denied

**Symptom**: Service can't read secret

**Solutions**:
1. Check `owner` matches service user
2. Verify `mode` allows reading
3. Check service runs as correct user
4. Add service user to secret's group

### Issue: Secret not updated

**Symptom**: Old value persists after update

**Solutions**:
1. Rebuild system: `nixos-rebuild switch`
2. Restart service: `systemctl restart myapp`
3. Use `restartUnits` option for auto-restart
4. Check SOPS decrypted correctly

## Reference

### SOPS Module Documentation
- NixOS SOPS-nix: https://github.com/Mic92/sops-nix
- SOPS tool: https://github.com/mozilla/sops

### Repository-Specific
- See `docs/agents/sops-secrets.md` for SOPS workflow in this repo
- See `modules/sops.nix` for SOPS module implementation
- See `secrets/secrets.yaml` for secret storage

### Example Modules with Secrets
- `modules/services/attic-client.nix` - Token file pattern
- `modules/services/atticd.nix` - Environment file pattern
- `modules/services/komodo.nix` - Multiple secrets pattern
