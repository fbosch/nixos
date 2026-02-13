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
        };

        sessionPath = [
          "$HOME/.local/share/pnpm"
        ];

        activation.installNpmGlobalPackages = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
          pnpm_home="$HOME/.local/share/pnpm"
          state_dir="$HOME/.local/state/pnpm-globals"

          mkdir -p "$pnpm_home" "$state_dir"

          # Add node, pnpm, and bun to PATH for postinstall scripts
          export PNPM_HOME="$pnpm_home"
          export PATH="$pnpm_home:${pkgs.nodejs_24}/bin:${pkgs.nodePackages.pnpm}/bin:${pkgs.bun}/bin:$PATH"

          if ${pkgs.nodePackages.pnpm}/bin/pnpm add -g ${lib.concatStringsSep " " (map lib.escapeShellArg npmGlobalPackages)} 2>&1; then
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
