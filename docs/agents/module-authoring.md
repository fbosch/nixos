# Module Authoring Rules

1. **Declare modules, don't import paths**
   - Each module file exports the configuration snippet under its desired key in `flake.modules.*`.
   - Consumers reference `config.flake.modules.<namespace>.<name>` by attribute path only.
2. **Keep NixOS and Home Manager siblings together when related**
   - Co-locate system-level and user-level logic in the same file by populating both `flake.modules.nixos.*` and `flake.modules.homeManager.*` entries.
3. **Derive host builds from module lists**
   - Host definitions only list module keys; the loader handles expansion, Home Manager wiring, and installer-specific extras.
4. **Use metadata instead of literals**
   - Pull shared strings, secrets, and UI options from `config.flake.meta` so replacements propagate automatically.
5. **Route dependencies through the tree**
   - When a feature depends on another, import it using `config.flake.modules` (e.g. `imports = [ config.flake.modules.nixos.<other> ];`) rather than relative file paths.
6. **Expose automation through perSystem**
   - Checks, formatters, dev shells, and packages should be defined under `perSystem` so every supported platform gets consistent tooling.
7. **Prefer data over conditionals**
   - Pass environment-specific values (host role, install mode, usernames) in `specialArgs` to keep modules declarative and easily testable.
8. **Keep comments minimal**
   - Only add comments that explain "why", not "what"; remove obvious restatements.
   - Avoid section headers unless the file is complex enough to warrant them; brief inline comments for non-obvious values are acceptable.

## Self-Contained Service Modules

Service modules should be self-contained with sensible defaults, allowing hosts to simply import them without additional configuration. This follows the dendritic pattern of "import to enable."

### Pattern: Import to Enable

Modules should NOT have top-level `enable` options. Importing the module enables the service with good defaults.

**❌ Anti-pattern:**
```nix
# Module defines enable option
options.services.myapp.enable = lib.mkEnableOption "My App";

config = lib.mkIf cfg.enable {
  services.myapp = { ... };
};

# Host must explicitly enable
services.myapp.enable = true;
```

**✅ Correct pattern:**
```nix
# Module enables by default
flake.modules.nixos."services/myapp" = {
  config = {
    services.myapp.enable = lib.mkDefault true;
    services.myapp.port = lib.mkDefault 8080;
    # ... all configuration with good defaults
  };
};

# Host just imports - no enable needed!
imports = [ "services/myapp" ];

# Only override if different from defaults
services.myapp.port = 9000;
```

### Namespace Guidelines

**For services that exist in nixpkgs (nginx, plex, postgresql):**
- Use `options.services.<name>` for custom options (if needed)
- Configure the nixpkgs service directly with `lib.mkDefault` for all values
- Example: `services.plex.enable = lib.mkDefault true;`

**For custom services (komodo, pihole-container, tinyproxy):**
- Use `options.services.<name>` for parameterization
- Keep all configuration in the module with good defaults
- Example: `options.services.komodo.core.port = lib.mkOption { default = 9120; }`

**Why `services.*` and not `modules.*` for options?**
1. Follows NixOS conventions - service options belong in `services.*` namespace
2. Low collision risk - truly custom services unlikely to be mainlined
3. If nixpkgs adds the service later, migration is straightforward (remove custom options, use nixpkgs options)
4. Dendritic pattern doesn't require custom namespaces for options

### Complete Example

```nix
# modules/services/tinyproxy.nix
_: {
  flake.modules.nixos."services/tinyproxy" = { config, lib, ... }:
    let
      cfg = config.services.tinyproxy;
    in
    {
      # Define options for parameterization (no enable option!)
      options.services.tinyproxy = {
        port = lib.mkOption {
          type = lib.types.port;
          default = 8888;
          description = "Port to listen on for proxy connections.";
        };

        listenAddress = lib.mkOption {
          type = lib.types.str;
          default = "0.0.0.0";
          description = "Address to bind the proxy server to.";
        };

        allowedClients = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ "192.168.1.0/24" ];
          description = "Allowed client IP addresses or CIDR ranges.";
        };
      };

      # Configure everything with good defaults (no mkIf cfg.enable!)
      config = {
        services.tinyproxy = {
          enable = lib.mkDefault true;
          settings = {
            Port = cfg.port;
            Listen = cfg.listenAddress;
            Allow = cfg.allowedClients;
          };
        };

        networking.firewall.allowedTCPPorts = [ cfg.port ];

        # Add related configuration (users, systemd services, etc.)
        users.users.tinyproxy.extraGroups = [ "users" ];
      };
    };
}
```

```nix
# modules/hosts/my-server.nix
{
  imports = [
    "services/tinyproxy"  # Enabled with defaults!
    "services/plex"       # Enabled with defaults!
  ];

  # Only override what's different from defaults
  services.tinyproxy.port = 9999;
  services.plex.nginx.port = 32402;
}
```

### Benefits

1. **Host files stay clean** - Just import, no boilerplate enable calls
2. **DRY principle** - Configuration lives in one place (the module)
3. **Good defaults** - Services work out of the box
4. **Easy overrides** - Use `lib.mkDefault` so hosts can override
5. **Dendritic compliance** - Follows "import to enable" pattern
6. **Future-proof** - If nixpkgs adds the service, easy to migrate
