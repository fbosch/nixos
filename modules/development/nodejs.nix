{
  flake.modules.homeManager.development =
    { pkgs
    , lib
    , ...
    }:
    let
      npmGlobalsRepoDir = "$HOME/nixos/modules/development/npm-globals";
      pnpmHome = if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "$HOME/.local/share/pnpm";
      pnpmStoreDir = "${pnpmHome}/store";

      installNpmGlobalPackagesScript = pkgs.writeShellApplication {
        name = "install-npm-global-packages";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.pnpm
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = builtins.readFile ./npm-globals/install-global-packages.sh;
      };

      updateNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-update";
        runtimeInputs = [
          pkgs.pnpm
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="$PNPM_HOME:${pkgs.nodejs_24}/bin:${pkgs.pnpm}/bin:${pkgs.bun}/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_globals_dir="''${1:-${npmGlobalsRepoDir}}"

          mkdir -p "$PNPM_HOME" "$PNPM_STORE_DIR" "$state_dir"

          if [ ! -f "$npm_globals_dir/package.json" ]; then
            echo "ERROR: package.json not found in: $npm_globals_dir" >&2
            echo "Pass an explicit directory: pnpm-global-update /path/to/modules/development/npm-globals" >&2
            exit 1
          fi

          echo "Refreshing pnpm lockfile from package.json specifiers..."
          (
            cd "$npm_globals_dir"
            pnpm install --lockfile-only
          )

          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$state_dir"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pkgs.pnpm}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pkgs.pnpm}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="$npm_globals_dir/pnpm-lock.yaml"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages

          echo ""
          echo "Lockfile refreshed and global npm packages updated."
          echo "Review and commit lockfile changes in: $npm_globals_dir/pnpm-lock.yaml"
        '';
      };

      installNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-install";
        runtimeInputs = [
          pkgs.pnpm
          pkgs.nodejs_24
          pkgs.bun
          pkgs.yq-go
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="$PNPM_HOME:${pkgs.nodejs_24}/bin:${pkgs.pnpm}/bin:${pkgs.bun}/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_globals_dir="''${1:-${npmGlobalsRepoDir}}"

          mkdir -p "$PNPM_HOME" "$PNPM_STORE_DIR" "$state_dir"

          if [ ! -f "$npm_globals_dir/pnpm-lock.yaml" ]; then
            echo "ERROR: pnpm-lock.yaml not found in: $npm_globals_dir" >&2
            echo "Run 'pnpm-global-update $npm_globals_dir' to generate it from package.json." >&2
            exit 1
          fi

          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$state_dir"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pkgs.pnpm}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pkgs.pnpm}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="$npm_globals_dir/pnpm-lock.yaml"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages
        '';
      };

    in
    {
      home = {
        packages = with pkgs; [
          fnm
          bun
          nodejs_24
          pnpm
          yarn
          # Prefer Nix packages for better reproducibility
          typescript
          prettier
          eslint
          npm-check-updates
          typescript-language-server
          prettierd
          playwright-test # Pure Nix Playwright with pre-configured browsers
          updateNodePackages
          installNodePackages
        ];

        sessionVariables = {
          PNPM_HOME = pnpmHome;
          PNPM_STORE_DIR = pnpmStoreDir;
        };

        sessionPath = [
          "$HOME/.local/bin"
          pnpmHome
        ];

        activation.installNpmGlobalPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          export PNPM_HOME_VALUE="${pnpmHome}"
          export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
          export STATE_DIR_VALUE="$HOME/.local/state/pnpm-globals"
          export NPM_REGISTRY_HOST="registry.npmjs.org"
          export PNPM_BIN="${pkgs.pnpm}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pkgs.pnpm}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LOCKFILE_PATH="${./npm-globals/pnpm-lock.yaml}"
          export YQ_BIN="${pkgs.yq-go}/bin/yq"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages
        '';
      };
    };
}
