#!/bin/sh
# Start Hyprland with UWSM (Universal Wayland Session Manager)
# The -F flag hardcodes the command line for proper systemd unit management
# Log output for debugging
exec uwsm start -F hyprland-uwsm.desktop >> /tmp/hyprland-start.log 2>&1
