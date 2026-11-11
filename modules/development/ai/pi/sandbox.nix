# Pi sandbox policy: what the nono launcher grants and protects. Other modules extend it, for
# example `pi.sandbox.filesystem.grants.ruff-cache = { … };` or
# `pi.sandbox.filesystem.grants.pi-lens.enable = false;`. The build validates the result against
# nono/scripts/shared/sandbox-policy.schema.json and ipc/capabilities.schema.json.
{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.pi.sandbox;
  defaults = lib.importJSON ../nono/scripts/shared/sandbox-policy.json;

  # Lists from several modules are concatenated. Grant order carries no meaning.
  list = description: mkOption { type = types.listOf types.str; inherit description; };
  base = types.enum [ "home" "config" "cache" "data" ];

  grant = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to grant this entry. Disabling it does not deny access another grant allows.";
      };
      base = mkOption {
        type = base;
        description = "home is $HOME; config, cache and data follow XDG_*_HOME from the launcher's own environment.";
      };
      path = mkOption { type = types.str; description = "Path below `base`, without `..` segments."; };
      override = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Variable in the launcher's own environment that replaces the whole location. Never read from a project .envrc.";
      };
      type = mkOption { type = types.enum [ "directory" "file" ]; };
      access = mkOption { type = types.enum [ "read" "readwrite" ]; };
    };
  };
in
{
  options.pi.sandbox = {
    filesystem = {
      grants = mkOption {
        type = types.attrsOf grant;
        description = "Tool state shared with the host, granted only when it exists. Every tool in the Pi session shares these grants.";
      };
      agent = {
        writableHomePaths = list "Writable directories below $HOME that Pi uses besides its agent directory.";
        runtimeEntries = list "Agent-directory entries that stay writable in locked-down sessions.";
        controlEntries = list "Agent-directory entries that are always protected, even when missing.";
      };
      shellStartup = {
        home = list "Shell startup paths below $HOME to keep read-only.";
        config = list "Shell startup paths below both config directories ($HOME/.config and XDG_CONFIG_HOME).";
        cache = list "Shell startup paths below both cache directories.";
        data = list "Shell startup paths below both data directories.";
      };
      runtimeDirectory = {
        secrets = list "XDG_RUNTIME_DIR entries no grant may reach.";
        services = list "XDG_RUNTIME_DIR directories created before granting, for tools that cannot create them.";
      };
    };

    ssh = {
      publicFiles = list "Public files in ~/.ssh the sandbox may read. The schema rejects anything but config, known_hosts* and *.pub.";
      agentIdentities = list "Keys in ~/.ssh the host launcher ensures are usable in its SSH agent. Never granted to the sandbox.";
    };

    exceptions.configurationRepositories = mkOption {
      # uniq: widening Pi-configuration write access requires replacing the list with mkForce.
      type = types.uniq (types.listOf types.str);
      description = "Directories below $HOME whose sessions may edit Pi setup. Replace with mkForce; other modules cannot append.";
    };

    ipc.registry = mkOption {
      type = types.attrsOf types.anything;
      default = lib.importJSON ../nono/scripts/ipc/capabilities.json;
      description = "IPC capability catalog and profile selections. Declaring a capability does not select it.";
    };

    launcherPolicy = mkOption {
      type = types.attrsOf types.anything;
      internal = true;
      readOnly = true;
      description = "The policy in the launcher's JSON format: enabled grants only, without enable markers or null overrides.";
    };
  };

  config.pi.sandbox = {
    # Definitions, not option defaults: other modules extend these lists instead of replacing them,
    # and mkDefault lets them change a shipped grant's fields.
    filesystem = defaults.filesystem // {
      grants = lib.mapAttrs (_: lib.mapAttrs (_: lib.mkDefault)) defaults.filesystem.grants;
    };
    inherit (defaults) ssh exceptions;

    launcherPolicy = {
      inherit (defaults) version;
      inherit (cfg) ssh exceptions;
      filesystem = cfg.filesystem // {
        grants = lib.mapAttrs
          (_: entry: lib.filterAttrs (name: value: name != "enable" && value != null) entry)
          (lib.filterAttrs (_: entry: entry.enable) cfg.filesystem.grants);
      };
    };
  };
}
