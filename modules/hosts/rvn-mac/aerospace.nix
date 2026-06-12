{
  flake.modules.darwin."hosts/rvn-mac/aerospace" = {
    services.aerospace = {
      enable = true;
      settings = {
        on-focus-changed = [ "move-mouse window-lazy-center" ];
        on-focused-monitor-changed = [ "move-mouse window-lazy-center" ];

        workspace-to-monitor-force-assignment = {
          "1" = [ "^DELL U2717D$" "built-in" "main" ];
          "2" = [ "^DELL P2721Q$" "built-in" "main" ];
          "3" = [ "^Built-in Retina Display$" "main" ];
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
          ctrl-alt-space = "exec-and-forget open -a Raycast";
          alt-backtick = "exec-and-forget open 'cleanshot://record-screen'";
          ctrl-alt-v = "layout floating tiling";
          ctrl-alt-f = "fullscreen";
          cmd-shift-f = "macos-native-fullscreen";
          cmd-b = "exec-and-forget app=app.zen-browser.zen; ws=$(/run/current-system/sw/bin/aerospace list-workspaces --focused); before=$(/run/current-system/sw/bin/aerospace list-windows --monitor all --app-bundle-id $app --format '%{window-id}'); /usr/bin/open -nb $app --args --new-window about:blank >/dev/null 2>&1; for i in {1..50}; do sleep 0.1; after=$(/run/current-system/sw/bin/aerospace list-windows --monitor all --app-bundle-id $app --format '%{window-id}'); for id in $after; do case \" $before \" in *\" $id \"*) ;; *) /run/current-system/sw/bin/aerospace move-node-to-workspace --focus-follows-window --window-id $id $ws; exit 0;; esac; done; done; /usr/bin/open -b $app";

          cmd-h = "focus --boundaries all-monitors-outer-frame left";
          cmd-l = "focus --boundaries all-monitors-outer-frame right";
          cmd-j = "focus --boundaries all-monitors-outer-frame down";
          cmd-k = "focus --boundaries all-monitors-outer-frame up";

          cmd-shift-h = "exec-and-forget id=$(/run/current-system/sw/bin/aerospace list-windows --focused --format '%{window-id}') && /run/current-system/sw/bin/aerospace move --window-id $id --boundaries all-monitors-outer-frame --boundaries-action stop left && /run/current-system/sw/bin/aerospace focus --window-id $id";
          cmd-shift-l = "exec-and-forget id=$(/run/current-system/sw/bin/aerospace list-windows --focused --format '%{window-id}') && /run/current-system/sw/bin/aerospace move --window-id $id --boundaries all-monitors-outer-frame --boundaries-action stop right && /run/current-system/sw/bin/aerospace focus --window-id $id";
          cmd-shift-j = "exec-and-forget id=$(/run/current-system/sw/bin/aerospace list-windows --focused --format '%{window-id}') && /run/current-system/sw/bin/aerospace move --window-id $id --boundaries all-monitors-outer-frame --boundaries-action stop down && /run/current-system/sw/bin/aerospace focus --window-id $id";
          cmd-shift-k = "exec-and-forget id=$(/run/current-system/sw/bin/aerospace list-windows --focused --format '%{window-id}') && /run/current-system/sw/bin/aerospace move --window-id $id --boundaries all-monitors-outer-frame --boundaries-action stop up && /run/current-system/sw/bin/aerospace focus --window-id $id";

          cmd-right = "resize width +50";
          cmd-left = "resize width -50";
          cmd-up = "resize height +50";
          cmd-down = "resize height -50";

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

          cmd-shift-1 = "move-node-to-workspace --focus-follows-window 1";
          cmd-shift-2 = "move-node-to-workspace --focus-follows-window 2";
          cmd-shift-3 = "move-node-to-workspace --focus-follows-window 3";
          cmd-shift-4 = "move-node-to-workspace --focus-follows-window 4";
          cmd-shift-5 = "move-node-to-workspace --focus-follows-window 5";
          cmd-shift-6 = "move-node-to-workspace --focus-follows-window 6";
          cmd-shift-7 = "move-node-to-workspace --focus-follows-window 7";
          cmd-shift-8 = "move-node-to-workspace --focus-follows-window 8";
          cmd-shift-9 = "move-node-to-workspace --focus-follows-window 9";
          cmd-shift-0 = "move-node-to-workspace --focus-follows-window 10";
        };
      };
    };
  };
}
