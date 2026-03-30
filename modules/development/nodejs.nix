{
  flake.modules.homeManager.development =
    { pkgs
    , lib
    , config
    , ...
    }:
    let
      # Packages installed via npm global (not available or outdated in nixpkgs)
      # Format: "package[@version]" - pin versions for reproducibility
      npmGlobalPackages = [
        "pokemonshow@latest" # Pokemon Showdown - not in nixpkgs
        "corepack@latest" # Node.js package manager manager
        "@fsouza/prettierd@latest" # Faster prettier daemon
        "opencode-ai@latest" # AI code assistant
        "neovim@latest" # Neovim npm package
        "typescript-language-server@latest" # TS LSP server
        "vercel@latest" # Vercel CLI
        "@github/copilot@latest" # Copilot CLI
        "agent-browser@latest" # headless browser for AI Agents
        "opencode-claude-auth@latest"
        "@schpet/linear-cli@latest" # linear-cli
        # "dorita980" # Roomba password
      ];

      pinnedNpmGlobalPackages = lib.filter (pkg: !(lib.hasSuffix "@latest" pkg)) npmGlobalPackages;
      latestNpmGlobalPackages = lib.filter (pkg: lib.hasSuffix "@latest" pkg) npmGlobalPackages;
      pnpmHome = if pkgs.stdenv.isDarwin then "$HOME/Library/pnpm" else "$HOME/.local/share/pnpm";
      pnpmStoreDir = "${pnpmHome}/store";

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
            echo "Updating @latest packages..."
            pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg latestNpmGlobalPackages)}
          ''}

          ${lib.optionalString (pinnedNpmGlobalPackages != [ ]) ''
            echo "Enforcing pinned package versions..."
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
          pnpm_home="${pnpmHome}"
          pnpm_store_dir="${pnpmStoreDir}"
          state_dir="$HOME/.local/state/pnpm-globals"
          npm_registry_host="registry.npmjs.org"

          mkdir -p "$pnpm_home" "$pnpm_store_dir" "$state_dir"

          # Add node, pnpm, and bun to PATH for postinstall scripts
          export PNPM_HOME="$pnpm_home"
          export PNPM_STORE_DIR="$pnpm_store_dir"
          export PATH="$pnpm_home:${pkgs.nodejs_24}/bin:${pkgs.nodePackages.pnpm}/bin:${pkgs.bun}/bin:$PATH"

          # Only run installs when a new Home Manager generation is activated
          # (e.g. via `home-manager switch`), not on every subsequent activation.
          if [ -n "''${oldGenPath:-}" ] && [ "''${oldGenPath}" = "''${newGenPath:-}" ]; then
            echo "Home Manager generation unchanged, skipping npm global update"
            exit 0
          fi

          # Do not block boot/login path. Boot-time Home Manager activation runs
          # without a user service manager; defer npm global updates on Linux
          # until the user systemd instance is ready.
          if command -v systemctl >/dev/null 2>&1 && ! systemctl --user show-environment >/dev/null 2>&1; then
            echo "User systemd daemon not running, skipping npm global update during boot activation"
            exit 0
          fi

          # Wait for DNS/network before trying npm registry operations.
          resolve_host() {
            if command -v getent >/dev/null 2>&1; then
              getent hosts "$1" >/dev/null 2>&1
            elif command -v dscacheutil >/dev/null 2>&1; then
              dscacheutil -q host -a name "$1" >/dev/null 2>&1
            else
              return 0
            fi
          }

          network_ready=0
          for _ in $(seq 1 30); do
            if resolve_host "$npm_registry_host"; then
              network_ready=1
              break
            fi
            sleep 1
          done

          if [ "$network_ready" -ne 1 ]; then
            echo "WARNING: network not ready for $npm_registry_host, skipping npm global update" >&2
            exit 0
          fi

          install_failed=0

          if [ "${if latestNpmGlobalPackages != [ ] then "true" else "false"}" = "true" ]; then
            echo "Installing/updating @latest npm global packages..."
            if ! ${pkgs.nodePackages.pnpm}/bin/pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg latestNpmGlobalPackages)} 2>&1; then
              install_failed=1
            fi
          fi

          if [ "${if pinnedNpmGlobalPackages != [ ] then "true" else "false"}" = "true" ]; then
            echo "Enforcing pinned npm global package versions..."
            if ! ${pkgs.nodePackages.pnpm}/bin/pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg pinnedNpmGlobalPackages)} 2>&1; then
              install_failed=1
            fi
          fi

          if [ "$install_failed" -eq 0 ]; then
            pnpm_global_dir="$(${pkgs.nodePackages.pnpm}/bin/pnpm root -g)"
            echo ""
            echo "npm global packages are up to date in: $pnpm_global_dir"
          else
            echo ""
            echo "WARNING: Failed to install/update npm global packages." >&2
            echo "Run 'home-manager switch' again to retry." >&2
          fi
        '';
      };
    };
}
