_: {
  flake.modules.homeManager.system = { lib, pkgs, config, ... }:
    let
      flakeCheckScript = pkgs.writeShellScriptBin "flake-check-updates" ''
        CACHE_FILE="''${XDG_CACHE_HOME:-$HOME/.cache}/flake-updates.json"
        FLAKE_PATH="''${1:-$HOME/nixos}"

        # Ensure cache directory exists
        mkdir -p "$(dirname "$CACHE_FILE")"

        # Check if flake.lock exists
        if [ ! -f "$FLAKE_PATH/flake.lock" ]; then
          echo '{"count": 0, "updates": [], "error": "No flake.lock found"}' > "$CACHE_FILE"
          exit 1
        fi

        cd "$FLAKE_PATH" || exit 1

        # Get all inputs from flake metadata
        FLAKE_DATA=$(${pkgs.jq}/bin/jq '.' flake.lock 2>/dev/null)
        ROOT_INPUTS=$(echo "$FLAKE_DATA" | ${pkgs.jq}/bin/jq -r '.nodes.root.inputs' 2>/dev/null)

        if [ -z "$ROOT_INPUTS" ] || [ "$ROOT_INPUTS" = "null" ]; then
          echo '{"count": 0, "updates": [], "error": "Failed to get flake inputs"}' > "$CACHE_FILE"
          exit 1
        fi

        INPUT_LIST=$(echo "$ROOT_INPUTS" | ${pkgs.jq}/bin/jq -r 'keys[]' 2>/dev/null)

        # Create temporary backup of lock file
        LOCK_BACKUP=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.coreutils}/bin/cp flake.lock "$LOCK_BACKUP"

        # Check each input for available updates
        UPDATES_JSON="[]"

        for INPUT in $INPUT_LIST; do
          # Restore original lock file before each check
          ${pkgs.coreutils}/bin/cp "$LOCK_BACKUP" flake.lock

          # Get current revision from lock file
          NODE_NAME=$(echo "$ROOT_INPUTS" | ${pkgs.jq}/bin/jq -r ".[\"$INPUT\"]" 2>/dev/null)
          [ -z "$NODE_NAME" ] || [ "$NODE_NAME" = "null" ] && continue

          NODE_DATA=$(echo "$FLAKE_DATA" | ${pkgs.jq}/bin/jq ".nodes.\"$NODE_NAME\"" 2>/dev/null)
          [ -z "$NODE_DATA" ] || [ "$NODE_DATA" = "null" ] && continue

          CURRENT_REV=$(echo "$NODE_DATA" | ${pkgs.jq}/bin/jq -r '.locked.rev // empty' 2>/dev/null)
          [ -z "$CURRENT_REV" ] || [ "$CURRENT_REV" = "null" ] && continue

          # Try to update this input (completely silent)
          ${pkgs.nix}/bin/nix flake update --update-input "$INPUT" >/dev/null 2>&1

          # Check if the lock file changed by comparing the revision
          UPDATED_FLAKE_DATA=$(${pkgs.jq}/bin/jq '.' flake.lock 2>/dev/null)
          UPDATED_NODE_DATA=$(echo "$UPDATED_FLAKE_DATA" | ${pkgs.jq}/bin/jq ".nodes.\"$NODE_NAME\"" 2>/dev/null)
          
          if [ -n "$UPDATED_NODE_DATA" ] && [ "$UPDATED_NODE_DATA" != "null" ]; then
            NEW_REV=$(echo "$UPDATED_NODE_DATA" | ${pkgs.jq}/bin/jq -r '.locked.rev // empty' 2>/dev/null)
            
            if [ -n "$NEW_REV" ] && [ "$NEW_REV" != "null" ] && [ "$NEW_REV" != "$CURRENT_REV" ]; then
              # Get short versions for display
              CURRENT_SHORT=$(echo "$CURRENT_REV" | ${pkgs.coreutils}/bin/cut -c1-7)
              NEW_SHORT=$(echo "$NEW_REV" | ${pkgs.coreutils}/bin/cut -c1-7)
              
              # Add update info to JSON array
              UPDATE_OBJ=$(${pkgs.jq}/bin/jq -n \
                --arg name "$INPUT" \
                --arg currentRev "$CURRENT_REV" \
                --arg currentShort "$CURRENT_SHORT" \
                --arg newRev "$NEW_REV" \
                --arg newShort "$NEW_SHORT" \
                '{name: $name, currentRev: $currentRev, currentShort: $currentShort, newRev: $newRev, newShort: $newShort}')
              
              UPDATES_JSON=$(echo "$UPDATES_JSON" | ${pkgs.jq}/bin/jq --argjson item "$UPDATE_OBJ" '. += [$item]')
            fi
          fi
        done

        # Restore original lock file
        ${pkgs.coreutils}/bin/cp "$LOCK_BACKUP" flake.lock
        ${pkgs.coreutils}/bin/rm -f "$LOCK_BACKUP"

        # Build final JSON output with timestamp
        UPDATE_COUNT=$(echo "$UPDATES_JSON" | ${pkgs.jq}/bin/jq 'length')
        TIMESTAMP=$(${pkgs.coreutils}/bin/date -Iseconds)
        RESULT=$(${pkgs.jq}/bin/jq -n \
          --argjson count "$UPDATE_COUNT" \
          --argjson updates "$UPDATES_JSON" \
          --arg timestamp "$TIMESTAMP" \
          '{count: $count, updates: $updates, timestamp: $timestamp}')
        
        echo "$RESULT" > "$CACHE_FILE"
      '';
    in
    {
      home.packages = [ flakeCheckScript ];

      # Clear cache after rebuild to trigger re-evaluation
      home.activation.flakeUpdatesCache = lib.hm.dag.entryAfter [ "writeBoundary" ] "rm -f ${config.xdg.cacheHome}/flake-updates.json || true";

      # Systemd service to check for flake updates
      systemd.user.services.flake-update-checker = {
        Unit = {
          Description = "Check for available NixOS flake updates";
        };

        Service = {
          Type = "oneshot";
          ExecStart = "${flakeCheckScript}/bin/flake-check-updates ${config.home.homeDirectory}/nixos";
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
