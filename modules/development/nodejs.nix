{
  flake.modules.homeManager.development =
    { pkgs
    , lib
    , config
    , ...
    }:
    let
      npmGlobalsManifest = builtins.fromJSON (builtins.readFile ./npm-globals/package.json);
      npmGlobalPackages =
        lib.mapAttrsToList (name: version: "${name}@${version}")
          (npmGlobalsManifest.dependencies or { });
      pinnedNpmGlobalPackages = lib.filter (pkg: !(lib.hasSuffix "@latest" pkg)) npmGlobalPackages;
      latestNpmGlobalPackages = lib.filter (pkg: lib.hasSuffix "@latest" pkg) npmGlobalPackages;
      latestNpmGlobalPackagesFile = pkgs.writeText "npm-global-latest-packages.txt" (lib.concatStringsSep "\n" latestNpmGlobalPackages);
      pinnedNpmGlobalPackagesFile = pkgs.writeText "npm-global-pinned-packages.txt" (lib.concatStringsSep "\n" pinnedNpmGlobalPackages);
      pnpmHome = if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "$HOME/.local/share/pnpm";
      pnpmStoreDir = "${pnpmHome}/store";

      installNpmGlobalPackagesScript = pkgs.writeShellApplication {
        name = "install-npm-global-packages";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.nodePackages.pnpm
          pkgs.nodejs_24
          pkgs.bun
        ];
        text = builtins.readFile ./npm-globals/install-global-packages.sh;
      };

      updateNodePackages = pkgs.writeShellApplication {
        name = "pnpm-global-update";
        runtimeInputs = [
          pkgs.nodePackages.pnpm
          pkgs.nodejs_24
          pkgs.bun
        ];
        text = ''
          export PNPM_HOME="${pnpmHome}"
          export PNPM_STORE_DIR="${pnpmStoreDir}"
          export PATH="$PNPM_HOME:${pkgs.nodejs_24}/bin:${pkgs.nodePackages.pnpm}/bin:${pkgs.bun}/bin:$PATH"
          state_dir="$HOME/.local/state/pnpm-globals"

          mkdir -p "$PNPM_HOME" "$PNPM_STORE_DIR" "$state_dir"

          ${lib.optionalString (latestNpmGlobalPackages != [ ]) ''
            echo "Updating @latest packages declared in npm-globals/package.json..."
            pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg latestNpmGlobalPackages)}
          ''}

          ${lib.optionalString (pinnedNpmGlobalPackages != [ ]) ''
            echo "Enforcing pinned package versions declared in npm-globals/package.json..."
            pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg pinnedNpmGlobalPackages)}
          ''}

          echo ""
          echo "Global npm packages updated:"
          pnpm ls -g --depth=0
        '';
      };

    in
    {
      home = {
        packages = with pkgs; [
          fnm
          bun
          nodejs_24
          nodePackages.pnpm
          nodePackages.yarn
          # Prefer Nix packages for better reproducibility
          nodePackages.typescript
          nodePackages.prettier
          nodePackages.eslint
          nodePackages.npm-check-updates
          typescript-language-server
          prettierd
          playwright-test # Pure Nix Playwright with pre-configured browsers
          updateNodePackages
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
          export PNPM_BIN="${pkgs.nodePackages.pnpm}/bin/pnpm"
          export NODE_BIN_DIR="${pkgs.nodejs_24}/bin"
          export PNPM_BIN_DIR="${pkgs.nodePackages.pnpm}/bin"
          export BUN_BIN_DIR="${pkgs.bun}/bin"
          export LATEST_PACKAGES_FILE="${latestNpmGlobalPackagesFile}"
          export PINNED_PACKAGES_FILE="${pinnedNpmGlobalPackagesFile}"

          ${installNpmGlobalPackagesScript}/bin/install-npm-global-packages
        '';
      };
    };
}
