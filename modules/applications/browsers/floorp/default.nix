{
  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    {
      home.activation.floorpUserJs = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ]; then
          echo "Home Manager generation unchanged, skipping Floorp user.js setup"
          exit 0
        fi

        FLOORP_PROFILE="$HOME/.var/app/one.ablaze.floorp/.floorp"
        if [ -d "$FLOORP_PROFILE" ]; then
          ${pkgs.findutils}/bin/find "$FLOORP_PROFILE" -maxdepth 1 -iname "*default*" -type d ! -name "static-*" | while IFS= read -r PROFILE_DIR; do
            ${pkgs.coreutils}/bin/install -m 0644 ${./user.js} "$PROFILE_DIR/user.js"
            echo "Floorp user.js installed at $PROFILE_DIR/user.js"
          done
        fi
      '';

      services.flatpak.packages = [
        "one.ablaze.floorp"
      ];
    };
}
