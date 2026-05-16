{
  flake.modules.homeManager.development =
    { pkgs
    , lib
    , ...
    }:
    let
      npmGlobalsRepoDir = "$HOME/nixos/modules/development/npm-globals";
      pnpmPackage = pkgs.local.pnpm;
      pnpmHome = if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "$HOME/.local/share/pnpm";
      pnpmGlobalBinDir = "${pnpmHome}/bin";
      pnpmStoreDir = "${pnpmHome}/store";

      installNpmGlobalPackagesScript = pkgs.writeShellApplication {
        name = "install-npm-global-packages";
        runtimeInputs = [
          pkgs.coreutils
          pnpmPackage
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = builtins.readFile ./install-global-packages.sh;
      };

      updateNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-update";
        runtimeInputs = [
          pkgs.coreutils
          pnpmPackage
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="${pkgs.nodejs_24}/bin:${pnpmPackage}/bin:${pkgs.bun}/bin:$PNPM_HOME/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_globals_dir="''${1:-${npmGlobalsRepoDir}}"

          mkdir -p "$PNPM_HOME/bin" "$PNPM_STORE_DIR" "$state_dir"

          if [ ! -f "$npm_globals_dir/package.json" ]; then
            echo "ERROR: package.json not found in: $npm_globals_dir" >&2
            echo "Pass an explicit directory: pnpm-global-update /path/to/modules/development/npm-globals" >&2
            exit 1
          fi

          rm -rf "$npm_globals_dir/node_modules"

          echo "Updating pnpm lockfile to latest dependency releases..."
          (
            cd "$npm_globals_dir"
            pnpm update --latest --lockfile-only
          )

          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$state_dir"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pnpmPackage}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pnpmPackage}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="$npm_globals_dir/pnpm-lock.yaml"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages

          echo ""
          echo "Lockfile refreshed and global npm packages updated."
          echo "Review and commit lockfile changes in: $npm_globals_dir/pnpm-lock.yaml"
        '';
      };

      upgradeNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-upgrade";
        runtimeInputs = [
          pkgs.coreutils
          pnpmPackage
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="${pkgs.nodejs_24}/bin:${pnpmPackage}/bin:${pkgs.bun}/bin:$PNPM_HOME/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_globals_dir="''${1:-${npmGlobalsRepoDir}}"

          mkdir -p "$PNPM_HOME/bin" "$PNPM_STORE_DIR" "$state_dir"

          if [ ! -f "$npm_globals_dir/package.json" ]; then
            echo "ERROR: package.json not found in: $npm_globals_dir" >&2
            echo "Pass an explicit directory: pnpm-global-upgrade /path/to/modules/development/npm-globals" >&2
            exit 1
          fi

          rm -rf "$npm_globals_dir/node_modules"

          echo "Choose upgrades interactively (including majors) ..."
          (
            cd "$npm_globals_dir"
            pnpm update --interactive --latest
          )

          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$state_dir"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pnpmPackage}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pnpmPackage}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="$npm_globals_dir/pnpm-lock.yaml"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages

          echo ""
          echo "Interactive upgrade complete. Review and commit package.json + pnpm-lock.yaml in: $npm_globals_dir"
        '';
      };

      installNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-install";
        runtimeInputs = [
          pkgs.coreutils
          pnpmPackage
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="${pkgs.nodejs_24}/bin:${pnpmPackage}/bin:${pkgs.bun}/bin:$PNPM_HOME/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_globals_dir="''${1:-${npmGlobalsRepoDir}}"

          mkdir -p "$PNPM_HOME/bin" "$PNPM_STORE_DIR" "$state_dir"

          if [ ! -f "$npm_globals_dir/pnpm-lock.yaml" ]; then
            echo "ERROR: pnpm-lock.yaml not found in: $npm_globals_dir" >&2
            echo "Run 'pnpm-global-update $npm_globals_dir' to generate it from package.json." >&2
            exit 1
          fi

          rm -rf "$npm_globals_dir/node_modules"

          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$state_dir"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pnpmPackage}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pnpmPackage}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="$npm_globals_dir/pnpm-lock.yaml"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages
        '';
      };
    in
    {
      home = {
        packages = [
          updateNodePackages
          upgradeNodePackages
          installNodePackages
        ];

        sessionVariables = {
          PNPM_HOME = pnpmHome;
          PNPM_STORE_DIR = pnpmStoreDir;
        };

        sessionPath = [
          "$HOME/.local/bin"
          "/etc/profiles/per-user/$USER/bin"
          pnpmGlobalBinDir
        ];

      };
    };
}
