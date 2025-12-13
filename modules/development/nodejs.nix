{
  flake.modules.homeManager.development = { pkgs, lib, config, ... }:
    let
      npmGlobalPackages =
        [ "pokemonshow" "swpm" "@fsouza/prettierd" "opencode-ai" ];
    in
    {
      home = {
        packages = with pkgs; [
          fnm
          nodejs_22
          bun
          nodePackages.pnpm
          nodePackages.yarn
          nodePackages.typescript
          nodePackages.prettier
          nodePackages.eslint
          nodePackages.vercel
          nodePackages.npm-check-updates
          playwright-driver.browsers-chromium
        ];

        sessionVariables = {
          PNPM_HOME = "$HOME/.local/share/pnpm";
          NODE_PATH = "$HOME/.npm-packages/lib/node_modules";
          PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
        };

        sessionPath = [ "$HOME/.local/share/pnpm" "$HOME/.npm-packages/bin" ];

        file.".npmrc".text = ''
          prefix = ${config.home.homeDirectory}/.npm-packages
        '';

        activation.installNpmGlobalPackages =
          lib.hm.dag.entryAfter [ "linkGeneration" ] ''
            set -e

            npm_packages_dir="$HOME/.npm-packages"
            mkdir -p "$npm_packages_dir/bin" "$npm_packages_dir/lib/node_modules"

            # Ensure npm uses the correct prefix
            export npm_config_prefix="$npm_packages_dir"

            for package in ${
              lib.concatStringsSep " "
              (map lib.escapeShellArg npmGlobalPackages)
            }; do
              # Extract package name for checking (handle scoped packages)
              if [[ "$package" =~ ^@ ]]; then
                # Scoped package: @scope/name@version -> @scope/name
                package_name=$(echo "$package" | sed -E 's/@[0-9]+.*$//')
                # For scoped packages, check in the @scope subdirectory
                package_path="$npm_packages_dir/lib/node_modules/$package_name"
              else
                # Regular package: name@version -> name
                package_name=$(echo "$package" | cut -d'@' -f1)
                package_path="$npm_packages_dir/lib/node_modules/$package_name"
              fi

              # Check if package is already installed by checking the directory
              if [ -d "$package_path" ]; then
                echo "Package $package_name is already installed, skipping..."
              else
                echo "Installing $package globally..."
                if ! ${pkgs.nodejs_22}/bin/npm install -g "$package" 2>&1; then
                  echo "ERROR: Failed to install $package" >&2
                  echo "Check the npm output above for details" >&2
                else
                  echo "Successfully installed $package"
                fi
              fi
            done

            echo "Global npm packages installed to: $npm_packages_dir"
            echo "Packages should be available in new shell sessions"
            echo "For current session, run: export PATH=\"\$HOME/.npm-packages/bin:\$PATH\""
          '';
      };
    };
}
