let
  aerospace = "/run/current-system/sw/bin/aerospace";

  exec = command: "exec-and-forget ${command}";

  openZenBlankInCurrentWorkspace = exec "app=app.zen-browser.zen; aerospace=${aerospace}; ws=$($aerospace list-workspaces --focused); before=$($aerospace list-windows --monitor all --app-bundle-id $app --format '%{window-id}'); /usr/bin/open -nb $app --args --new-window about:blank >/dev/null 2>&1; for i in {1..50}; do sleep 0.1; after=$($aerospace list-windows --monitor all --app-bundle-id $app --format '%{window-id}'); for id in $after; do case \" $before \" in *\" $id \"*) ;; *) $aerospace move-node-to-workspace --focus-follows-window --window-id $id $ws; exit 0;; esac; done; done; /usr/bin/open -b $app";

  moveFocusedWindow = direction: exec "id=$(${aerospace} list-windows --focused --format '%{window-id}') && ${aerospace} move --window-id $id --boundaries all-monitors-outer-frame --boundaries-action stop ${direction} && ${aerospace} focus --window-id $id";

  moveNodeToWorkspace = workspace: "move-node-to-workspace --focus-follows-window ${workspace}";

  moveNodeToWorkspaceOnFocusedMonitor = workspace: exec "ws=${workspace}; aerospace=${aerospace}; id=$($aerospace list-windows --focused --format '%{window-id}') && ($aerospace list-workspaces --all --format '%{workspace}' | /usr/bin/grep -Fxq \"$ws\" || $aerospace summon-workspace \"$ws\") && $aerospace move-node-to-workspace --focus-follows-window --window-id $id \"$ws\"";
in
{
  flake.modules.darwin.aerospace = {
    services.aerospace = {
      enable = true;
      settings = {
        after-startup-command = [
          (exec "borders active_color=0xffe1e3e4 inactive_color=0x00000000 width=5.0")
        ];

        on-focus-changed = [ "move-mouse window-lazy-center" ];
        on-focused-monitor-changed = [ "move-mouse window-lazy-center" ];

        workspace-to-monitor-force-assignment = {
          "1" = [
            "^DELL U2717D$"
            "built-in"
            "main"
          ];
          "2" = [
            "^DELL P2721Q$"
            "built-in"
            "main"
          ];
          "3" = [
            "^Built-in Retina Display$"
            "main"
          ];
        };

        on-window-detected = [
          {
            "if".app-id = "com.microsoft.teams2";
            run = "move-node-to-workspace 1";
          }
          {
            "if".app-id = "com.tinyspeck.slackmacgap";
            run = "move-node-to-workspace 1";
          }
          {
            "if".app-id = "com.github.wez.wezterm";
            run = "move-node-to-workspace 2";
          }
          {
            "if".app-id = "app.zen-browser.zen";
            run = "move-node-to-workspace 3";
          }
        ];

        mode.main.binding = {
          ctrl-alt-space = exec "open -a Raycast";
          alt-backtick = exec "open 'cleanshot://record-screen'";
          ctrl-alt-v = "layout floating tiling";
          ctrl-alt-f = "fullscreen";
          cmd-shift-f = "macos-native-fullscreen";
          cmd-b = openZenBlankInCurrentWorkspace;

          cmd-h = "focus --boundaries all-monitors-outer-frame left";
          cmd-l = "focus --boundaries all-monitors-outer-frame right";
          cmd-j = "focus --boundaries all-monitors-outer-frame down";
          cmd-k = "focus --boundaries all-monitors-outer-frame up";

          # Move the focused window in the tree, crossing monitors at edges.
          # Re-focus by window id because AeroSpace `move` lacks a focus-follow flag.
          cmd-shift-h = moveFocusedWindow "left";
          cmd-shift-l = moveFocusedWindow "right";
          cmd-shift-j = moveFocusedWindow "down";
          cmd-shift-k = moveFocusedWindow "up";

          cmd-right = "resize width +50";
          cmd-left = "resize width -50";
          cmd-up = "resize height +50";
          cmd-down = "resize height -50";

          # Explicit monitor/workspace movement when the target is the display itself,
          # not a directional position inside the current tiling tree.
          ctrl-alt-shift-right = "move-node-to-monitor --focus-follows-window --wrap-around next";
          ctrl-alt-shift-left = "move-node-to-monitor --focus-follows-window --wrap-around prev";
          ctrl-alt-shift-up = "move-workspace-to-monitor --wrap-around prev";
          ctrl-alt-shift-down = "move-workspace-to-monitor --wrap-around next";

          cmd-1 = "workspace 1";
          cmd-2 = "workspace 2";
          cmd-3 = "workspace 3";
          cmd-4 = "workspace 4";
          cmd-5 = "workspace 5";
          cmd-6 = "workspace 6";
          cmd-7 = "workspace 7";
          cmd-8 = "workspace 8";
          cmd-9 = "workspace 9";
          cmd-0 = "workspace 10";

          cmd-shift-1 = moveNodeToWorkspace "1";
          cmd-shift-2 = moveNodeToWorkspace "2";
          cmd-shift-3 = moveNodeToWorkspace "3";
          cmd-shift-4 = moveNodeToWorkspaceOnFocusedMonitor "4";
          cmd-shift-5 = moveNodeToWorkspaceOnFocusedMonitor "5";
          cmd-shift-6 = moveNodeToWorkspaceOnFocusedMonitor "6";
          cmd-shift-7 = moveNodeToWorkspaceOnFocusedMonitor "7";
          cmd-shift-8 = moveNodeToWorkspaceOnFocusedMonitor "8";
          cmd-shift-9 = moveNodeToWorkspaceOnFocusedMonitor "9";
          cmd-shift-0 = moveNodeToWorkspaceOnFocusedMonitor "10";
        };
      };
    };
  };
}
