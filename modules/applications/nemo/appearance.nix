{
  flake.modules.homeManager.applications =
    { lib, ... }:
    {
      xdg.configFile = {
        # Nemo transparency for Hyprland compositor blur
        "gtk-3.0/nemo-transparency.css".text = ''
          /* Nemo transparency for compositor blur */
          window.nemo-window,
          window.nemo-window .background {
            background: transparent;
          }

          /* Paint the content area once to avoid nested alpha compositing. */
          window.nemo-window > grid > paned.horizontal {
            background: rgba(37, 37, 37, 0.82);
          }

          window.nemo-window .sidebar {
            background: transparent;
            border: none;
            box-shadow: none;
          }

          window.nemo-window .nemo-window-pane,
          window.nemo-window scrolledwindow,
          window.nemo-window viewport,
          window.nemo-window .view,
          window.nemo-window treeview,
          window.nemo-window iconview {
            background: transparent;
          }

          .nemo-window .primary-toolbar,
          .nemo-window toolbar {
            background-color: rgba(37, 37, 37, 0.82);
          }

          window.nemo-window > grid > paned.horizontal > separator {
            background: transparent;
            border: none;
            box-shadow: none;
            min-width: 1px;
            -gtk-icon-source: none;
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
            background-color: rgba(37, 37, 37, 0.70);
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
