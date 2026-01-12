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
      ];

      # Hash of package list to detect changes
      packagesHash = builtins.hashString "sha256" (lib.concatStringsSep "," npmGlobalPackages);
    in
    {
      home = {
        packages = with pkgs; [
          fnm
          nodejs_22
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
          NODE_PATH = "$HOME/.npm-packages/lib/node_modules";
        };

        sessionPath = [
          "$HOME/.local/share/pnpm"
          "$HOME/.npm-packages/bin"
        ];

        file.".npmrc".text = ''
          prefix = ${config.home.homeDirectory}/.npm-packages
        '';

        activation.installNpmGlobalPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          npm_packages_dir="$HOME/.npm-packages"
          state_dir="$HOME/.local/state/npm-globals"
          hash_file="$state_dir/packages.hash"
          current_hash="${packagesHash}"

          mkdir -p "$npm_packages_dir/bin" "$npm_packages_dir/lib/node_modules" "$state_dir"

          # Skip installation if package list hasn't changed
          if [ -f "$hash_file" ] && [ "$(cat "$hash_file")" = "$current_hash" ]; then
            echo "npm global packages unchanged, skipping installation"
            exit 0
          fi

          echo "Package list changed or first run, checking npm globals..."

          # Ensure npm uses the correct prefix
          export npm_config_prefix="$npm_packages_dir"

          # Add node and bun to PATH for postinstall scripts
          export PATH="${pkgs.nodejs_22}/bin:${pkgs.bun}/bin:$PATH"

          install_failed=0

          for package in ${lib.concatStringsSep " " (map lib.escapeShellArg npmGlobalPackages)}; do
            # Extract package name for checking (handle scoped packages)
            if [[ "$package" =~ ^@ ]]; then
              # Scoped package: @scope/name@version -> @scope/name
              package_name=$(echo "$package" | sed -E 's/(@[^@]+\/[^@]+)@?.*/\1/')
              package_path="$npm_packages_dir/lib/node_modules/$package_name"
            else
              # Regular package: name@version -> name
              package_name=$(echo "$package" | cut -d'@' -f1)
              package_path="$npm_packages_dir/lib/node_modules/$package_name"
            fi

            # Check if we need to install/update
            should_install=false
            if [ ! -d "$package_path" ]; then
              echo "Installing $package globally..."
              should_install=true
            else
              # Check if version differs (for packages with @version)
              if [[ "$package" == *@* ]] && [[ "$package" != *@latest ]]; then
                installed_version=$(${pkgs.nodejs_22}/bin/npm list -g --depth=0 "$package_name" 2>/dev/null | grep "$package_name" | sed -E 's/.*@([0-9.]+).*/\1/' || echo "")
                requested_version=$(echo "$package" | sed -E 's/.*@([0-9.]+).*/\1/')
                if [ "$installed_version" != "$requested_version" ]; then
                  echo "Updating $package_name from $installed_version to $requested_version..."
                  should_install=true
                fi
              fi
            fi

            if [ "$should_install" = true ]; then
              if ${pkgs.nodejs_22}/bin/npm install -g "$package" --no-fund --no-audit 2>&1; then
                echo "✓ Successfully installed $package"
              else
                echo "✗ ERROR: Failed to install $package" >&2
                install_failed=1
              fi
            else
              echo "✓ $package_name already installed"
            fi
          done

          if [ "$install_failed" -eq 0 ]; then
            # Save hash only if all installations succeeded
            echo "$current_hash" > "$hash_file"
            echo ""
            echo "All npm global packages installed successfully to: $npm_packages_dir"
          else
            echo ""
            echo "WARNING: Some packages failed to install. Hash not updated." >&2
            echo "Run 'home-manager switch' again to retry failed installations." >&2
            exit 1
          fi
        '';
      };
    };
}
