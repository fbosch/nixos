{
  flake.modules.homeManager.applications =
    { lib, ... }:
    {
      xdg.configFile = {
        # Nemo transparency for Hyprland compositor blur
        "gtk-3.0/nemo-transparency.css".text = ''
          /* Nemo transparency for compositor blur */
          .nemo-window,
          .nemo-window .background {
            background-color: rgba(37, 37, 37, 0.75);
          }

          .nemo-window .view,
          .nemo-window treeview,
          .nemo-window scrolledwindow {
            background-color: rgba(37, 37, 37, 0.75);
          }

          .nemo-window .sidebar {
            background-color: rgba(37, 37, 37, 0.75);
          }

          /* Windows 11-style blue selection color */
          .nemo-window .view:selected,
          .nemo-window iconview:selected,
          .nemo-window .view:selected:focus,
          .nemo-window iconview:selected:focus {
            background-color: rgba(0, 120, 212, 0.8);
            color: #ffffff;
          }

          /* Windows 11-style blue drag selection area (rubberband) */
          .nemo-window .view.rubberband,
          .nemo-window iconview.rubberband,
          .nemo-window rubberband {
            background-color: rgba(0, 120, 212, 0.3);
            border: 1px solid rgba(0, 120, 212, 0.8);
          }

          /* Address bar — less transparent than window body */
          .nemo-window .primary-toolbar entry,
          .nemo-window toolbar entry {
            background-color: rgba(37, 37, 37, 0.90);
            -gtk-secondary-caret-color: transparent;
          }
        '';

        # Append import to existing gtk.css (creates if doesn't exist)
        "gtk-3.0/gtk.css".text = lib.mkAfter ''
          @import 'nemo-transparency.css';
        '';
      };
    };
}
