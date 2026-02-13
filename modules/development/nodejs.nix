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
        "swpm@latest" # Switch package manager - not in nixpkgs
        "corepack@latest" # Node.js package manager manager
        "@fsouza/prettierd@latest" # Faster prettier daemon
        "opencode-ai@latest" # AI code assistant
        "neovim@latest" # Neovim npm package
        "typescript-language-server@latest" # TS LSP server
        # "dorita980" # Roomba password
      ];

      pinnedNpmGlobalPackages = lib.filter (pkg: !(lib.hasSuffix "@latest" pkg)) npmGlobalPackages;
      latestNpmGlobalPackages = lib.filter (pkg: lib.hasSuffix "@latest" pkg) npmGlobalPackages;

      pinnedPackagesHash = builtins.hashString "sha256" (lib.concatStringsSep "," pinnedNpmGlobalPackages);

    in
    {
      home = {
        packages = with pkgs; [
          fnm
          nodejs_24
          bun
          nodePackages.pnpm
          nodePackages.yarn
          # Prefer Nix packages for better reproducibility
          nodePackages.typescript
          nodePackages.prettier
          nodePackages.eslint
          nodePackages.vercel
          nodePackages.npm-check-updates
          playwright-test # Pure Nix Playwright with pre-configured browsers
        ];

        sessionVariables = {
          PNPM_HOME = "$HOME/.local/share/pnpm";
          PNPM_STORE_DIR = "$HOME/.local/share/pnpm/store";
        };

        sessionPath = [
          "$HOME/.local/share/pnpm"
        ];

        activation.installNpmGlobalPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          pnpm_home="$HOME/.local/share/pnpm"
          pnpm_store_dir="$HOME/.local/share/pnpm/store"
          state_dir="$HOME/.local/state/pnpm-globals"
          pinned_hash_file="$state_dir/pinned-packages.hash"
          current_pinned_hash="${pinnedPackagesHash}"

          mkdir -p "$pnpm_home" "$pnpm_store_dir" "$state_dir"

          # Add node, pnpm, and bun to PATH for postinstall scripts
          export PNPM_HOME="$pnpm_home"
          export PNPM_STORE_DIR="$pnpm_store_dir"
          export PATH="$pnpm_home:${pkgs.nodejs_24}/bin:${pkgs.nodePackages.pnpm}/bin:${pkgs.bun}/bin:$PATH"

          install_failed=0

          if [ "${if pinnedNpmGlobalPackages != [ ] then "true" else "false"}" = "true" ]; then
            if [ -f "$pinned_hash_file" ] && [ "$(cat "$pinned_hash_file")" = "$current_pinned_hash" ]; then
              echo "Pinned npm global packages unchanged, skipping pinned install"
            else
              echo "Installing/updating pinned npm global packages..."
              if ${pkgs.nodePackages.pnpm}/bin/pnpm add -g --prefer-offline ${lib.concatStringsSep " " (map lib.escapeShellArg pinnedNpmGlobalPackages)} 2>&1; then
                echo "$current_pinned_hash" > "$pinned_hash_file"
              else
                install_failed=1
              fi
            fi
          fi

          if [ "${if latestNpmGlobalPackages != [ ] then "true" else "false"}" = "true" ]; then
            echo "Installing/updating @latest npm global packages..."
            if ! ${pkgs.nodePackages.pnpm}/bin/pnpm add -g --prefer-offline ${lib.concatStringsSep " " (map lib.escapeShellArg latestNpmGlobalPackages)} 2>&1; then
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
            exit 1
          fi
        '';
      };
    };
}
