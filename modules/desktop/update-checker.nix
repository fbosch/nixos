{
  flake.modules.homeManager.desktop =
    { lib
    , pkgs
    , config
    , ...
    }:
    let
      flakeCheckScript = pkgs.writeShellScriptBin "flake-check-updates" ''
        set -euo pipefail

        CACHE_DIR="''${XDG_CACHE_HOME:-$HOME/.cache}"
        CACHE_FILE="$CACHE_DIR/flake-updates.json"
        FLATPAK_CACHE_FILE="$CACHE_DIR/flatpak-updates.json"
        FLAKE_PATH="''${1:-$HOME/nixos}"

        ${pkgs.coreutils}/bin/mkdir -p "$CACHE_DIR"
        if [ ! -f "$FLAKE_PATH/flake.lock" ]; then
          echo "flake-check-updates: no flake.lock found at $FLAKE_PATH" >&2
          exit 1
        fi

        UPDATES_JSON="[]"
        while IFS= read -r name; do
          current_rev=$(${pkgs.jq}/bin/jq -r --arg name "$name" '
            .nodes as $nodes
            | .nodes.root.inputs[$name] as $node_name
            | $nodes[$node_name].locked.rev // ""
          ' "$FLAKE_PATH/flake.lock")
          [ -n "$current_rev" ] || continue

          candidate_lock=$(${pkgs.coreutils}/bin/mktemp "$CACHE_DIR/flake-update-lock.XXXXXX")
          if ! ${pkgs.coreutils}/bin/timeout 60s ${pkgs.nix}/bin/nix flake update "$name" \
            --flake "$FLAKE_PATH" \
            --reference-lock-file "$FLAKE_PATH/flake.lock" \
            --output-lock-file "$candidate_lock" \
            >/dev/null 2>&1
          then
            ${pkgs.coreutils}/bin/rm -f "$candidate_lock"
            continue
          fi

          new_rev=$(${pkgs.jq}/bin/jq -r --arg name "$name" '
            .nodes as $nodes
            | .nodes.root.inputs[$name] as $node_name
            | $nodes[$node_name].locked.rev // ""
          ' "$candidate_lock")
          ${pkgs.coreutils}/bin/rm -f "$candidate_lock"

          [ -n "$new_rev" ] && [ "$new_rev" != "$current_rev" ] || continue

          update=$(${pkgs.jq}/bin/jq -n \
            --arg name "$name" \
            --arg currentRev "$current_rev" \
            --arg currentShort "''${current_rev:0:7}" \
            --arg newRev "$new_rev" \
            --arg newShort "''${new_rev:0:7}" \
            '{name: $name, currentRev: $currentRev, currentShort: $currentShort, newRev: $newRev, newShort: $newShort}')
          UPDATES_JSON=$(printf '%s' "$UPDATES_JSON" | ${pkgs.jq}/bin/jq --argjson update "$update" '. + [$update]')
        done < <(${pkgs.jq}/bin/jq -r '
          .nodes.root.inputs
          | to_entries[]
          | select(.value | type == "string")
          | .key
        ' "$FLAKE_PATH/flake.lock")

        timestamp=$(${pkgs.coreutils}/bin/date -Iseconds)
        cache_tmp=$(${pkgs.coreutils}/bin/mktemp "$CACHE_DIR/flake-updates.json.XXXXXX")
        ${pkgs.jq}/bin/jq -n \
          --argjson updates "$UPDATES_JSON" \
          --arg timestamp "$timestamp" \
          '{count: ($updates | length), updates: $updates, timestamp: $timestamp}' \
          > "$cache_tmp"
        ${pkgs.coreutils}/bin/mv "$cache_tmp" "$CACHE_FILE"

        FLATPAK_JSON="[]"
        while IFS=$'\t' read -r app version branch; do
          [ -n "$app" ] || continue
          current_version=$(${pkgs.flatpak}/bin/flatpak info --show-version "$app" 2>/dev/null || true)
          update=$(${pkgs.jq}/bin/jq -n \
            --arg app "$app" \
            --arg currentVersion "$current_version" \
            --arg newVersion "$version" \
            --arg branch "$branch" \
            '{app: $app, currentVersion: $currentVersion, newVersion: $newVersion, branch: $branch}')
          FLATPAK_JSON=$(printf '%s' "$FLATPAK_JSON" | ${pkgs.jq}/bin/jq --argjson update "$update" '. + [$update]')
        done < <(${pkgs.flatpak}/bin/flatpak remote-ls --app --updates --columns=application,version,branch 2>/dev/null || true)

        flatpak_cache_tmp=$(${pkgs.coreutils}/bin/mktemp "$CACHE_DIR/flatpak-updates.json.XXXXXX")
        ${pkgs.jq}/bin/jq -n \
          --argjson updates "$FLATPAK_JSON" \
          --arg timestamp "$timestamp" \
          '{count: ($updates | length), updates: $updates, timestamp: $timestamp}' \
          > "$flatpak_cache_tmp"
        ${pkgs.coreutils}/bin/mv "$flatpak_cache_tmp" "$FLATPAK_CACHE_FILE"
      '';
    in
    {
      home.packages = [ flakeCheckScript ];

      # Trigger update check after rebuild to ensure cache is current
      home.activation.flakeUpdatesCache = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ]; then
          echo "Home Manager generation unchanged, skipping flake update cache trigger"
        else
          if [ -n "''${DRY_RUN:-}" ]; then
            echo "Would trigger flake update check"
          else
            # Reload systemd user daemon to pick up any service changes
            systemctl --user daemon-reload 2>/dev/null || true
            # Trigger async check in background (don't wait for completion)
            systemctl --user start flake-update-checker.service 2>/dev/null || true &
          fi
        fi
      '';

      # Systemd service to check for flake updates
      systemd.user.services.flake-update-checker = {
        Unit = {
          Description = "Check for available NixOS flake updates";
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${flakeCheckScript}/bin/flake-check-updates ${config.home.homeDirectory}/nixos";
          Nice = 19;
          CPUWeight = 10;
          IOSchedulingClass = "idle";
          IOWeight = 10;
          # Run in a sandbox-like environment
          PrivateTmp = true;
          # Continue even if check fails
          SuccessExitStatus = "0 1";
        };
      };

      # Systemd timer to run the checker periodically
      systemd.user.timers.flake-update-checker = {
        Unit = {
          Description = "Timer for flake update checker";
        };

        Timer = {
          # Run every hour
          OnCalendar = "hourly";
          # Run 5 minutes after boot
          OnBootSec = "5min";
          # If the timer missed a run (system was off), run it on next boot
          Persistent = true;
          # Randomize start time by up to 10 minutes to avoid load spikes
          RandomizedDelaySec = "10min";
        };

        Install = {
          WantedBy = [ "timers.target" ];
        };
      };
    };
}
