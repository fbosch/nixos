{
  flake.modules.homeManager.development =
    { config
    , pkgs
    , lib
    , ...
    }:
    let
      npmGlobalsRepoDir = "$HOME/nixos/modules/development/npm-globals";
      pnpmPackage = pkgs.local.pnpm or pkgs.pnpm;
      pnpmHome = if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "$HOME/.local/share/pnpm";
      pnpmStoreDir = "${pnpmHome}/store";
      stateDir = "$HOME/.local/state/pnpm-globals";
      pnpmGlobalBinDir = "${stateDir}/current/node_modules/.bin";

      installNpmGlobalPackagesScript = pkgs.writeShellApplication {
        name = "install-npm-global-packages";
        runtimeInputs = [
          pkgs.coreutils
          pnpmPackage
          pkgs.nodejs_24
          pkgs.bun
        ];
        text = builtins.readFile ./install-global-packages.sh;
      };

      installEnv = lockfilePath: ''
        export PNPM_HOME_VALUE="${pnpmHome}"
        export PNPM_STORE_DIR_VALUE="${pnpmStoreDir}"
        export STATE_DIR_VALUE="${stateDir}"
        export NPM_REGISTRY_HOST="registry.npmjs.org"
        export PNPM_BIN="${pnpmPackage}/bin/pnpm"
        export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
        export PNPM_BIN_DIR="${pnpmPackage}/bin"
        export BUN_BIN_DIR="${pkgs.bun}/bin"
        export LOCKFILE_PATH="${lockfilePath}"
      '';

      mkPnpmGlobalsCommand =
        { name
        , requiredFile
        , missingHint
        , beforeInstall ? ""
        , successMessage ? ""
        ,
        }:
        pkgs.writeShellApplication {
          inherit name;
          runtimeInputs = [
            pkgs.coreutils
            pnpmPackage
            pkgs.nodejs_24
            pkgs.bun
          ];
          text = ''
            export PNPM_HOME="${pnpmHome}"
            export PNPM_STORE_DIR="${pnpmStoreDir}"
            export PATH="${pkgs.nodejs_24}/bin:${pnpmPackage}/bin:${pkgs.bun}/bin:${pnpmGlobalBinDir}:$PATH"
            state_dir="${stateDir}"
            npm_globals_dir="''${NPM_GLOBALS_DIR:-''${1:-${npmGlobalsRepoDir}}}"

            mkdir -p "$PNPM_HOME/bin" "$PNPM_STORE_DIR" "$state_dir"

            if [ ! -f "$npm_globals_dir/${requiredFile}" ]; then
              echo "ERROR: ${requiredFile} not found in: $npm_globals_dir" >&2
              echo "${missingHint}" >&2
              exit 1
            fi

            rm -rf "$npm_globals_dir/node_modules"

            ${beforeInstall}

            ${installEnv "$npm_globals_dir/pnpm-lock.yaml"}

            ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages

            ${successMessage}
          '';
        };

      updateNodePackages = mkPnpmGlobalsCommand {
        name = "pnpm-global-update";
        requiredFile = "package.json";
        missingHint = "Pass an explicit directory: pnpm-global-update /path/to/modules/development/npm-globals";
        beforeInstall = ''
          echo "Refreshing pnpm lockfile from pinned package.json versions..."
          (
            cd "$npm_globals_dir"
            pnpm install --lockfile-only
          )
        '';
        successMessage = ''
          echo ""
          echo "Lockfile refreshed and global npm packages updated."
          echo "Review and commit lockfile changes in: $npm_globals_dir/pnpm-lock.yaml"
        '';
      };

      upgradeNodePackages = mkPnpmGlobalsCommand {
        name = "pnpm-global-upgrade";
        requiredFile = "package.json";
        missingHint = "Pass an explicit directory: pnpm-global-upgrade /path/to/modules/development/npm-globals";
        beforeInstall = ''
          echo "Checking npm package versions..."
          (
            cd "$npm_globals_dir"

            mapfile -t dependencies < <(
              node -e 'const { dependencies = {} } = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); for (const [name, version] of Object.entries(dependencies)) console.log(name + "\t" + version);' package.json
            )

            package_names=()
            latest_versions=()
            for dependency in "''${dependencies[@]}"; do
              package_name="''${dependency%%$'\t'*}"
              latest_version="$(pnpm view "$package_name@latest" version --silent)"
              package_names+=("$package_name")
              latest_versions+=("$latest_version")
            done

            echo ""
            printf '%-4s %-32s %-12s %s\n' "No." "Package" "Current" "Latest"
            for index in "''${!dependencies[@]}"; do
              dependency="''${dependencies[$index]}"
              package_name="''${dependency%%$'\t'*}"
              current_version="''${dependency#*$'\t'}"
              printf '%-4s %-32s %-12s %s\n' "$((index + 1))" "$package_name" "$current_version" "''${latest_versions[$index]}"
            done

            if ! read -r -p "Packages to upgrade (numbers, ranges, all, or blank to cancel): " selection; then
              exit 0
            fi
            if [ -z "$selection" ]; then
              exit 0
            fi

            selected_packages=()
            declare -A selected_indices=()
            add_package() {
              local index="$1"
              if ((index < 1 || index > ''${#package_names[@]})); then
                echo "ERROR: package number $index is out of range" >&2
                exit 1
              fi
              if [ -n "''${selected_indices[$index]:-}" ]; then
                return
              fi
              selected_indices[$index]=1
              selected_packages+=("''${package_names[$((index - 1))]}")
            }

            if [ "$selection" = "all" ]; then
              for ((index = 1; index <= ''${#package_names[@]}; index++)); do
                add_package "$index"
              done
            else
              IFS=', ' read -r -a selections <<<"$selection"
              for selection_item in "''${selections[@]}"; do
                if [[ "$selection_item" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                  for ((index = ''${BASH_REMATCH[1]}; index <= ''${BASH_REMATCH[2]}; index++)); do
                    add_package "$index"
                  done
                elif [[ "$selection_item" =~ ^[0-9]+$ ]]; then
                  add_package "$selection_item"
                else
                  echo "ERROR: invalid selection: $selection_item" >&2
                  exit 1
                fi
              done
            fi

            pnpm --reporter=append-only update --latest "''${selected_packages[@]}"
          )
        '';
        successMessage = ''
          echo ""
          echo "Package upgrade complete. Review and commit package.json + pnpm-lock.yaml in: $npm_globals_dir"
        '';
      };

      installNodePackages = mkPnpmGlobalsCommand {
        name = "pnpm-global-install";
        requiredFile = "pnpm-lock.yaml";
        missingHint = "Run 'pnpm-global-update' to generate it from package.json.";
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
          NPM_CONFIG_STORE_DIR = pnpmStoreDir;
        };

        sessionPath = [
          "$HOME/.local/bin"
          "/etc/profiles/per-user/$USER/bin"
          pnpmGlobalBinDir
        ];

        activation.installNpmGlobalPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${installEnv "${config.home.homeDirectory}/nixos/modules/development/npm-globals/pnpm-lock.yaml"}
          export PNPM_GLOBALS_NON_BLOCKING=1
          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages || echo "WARNING: Failed to install/update npm global packages." >&2
        '';
      };
    };
}
