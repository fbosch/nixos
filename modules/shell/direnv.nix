{
  flake.modules.homeManager.shell = { pkgs, ... }: {
    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;

      # Automatically load .envrc files
      config = {
        global = {
          # Disable the hints about using direnv allow
          warn_timeout = "24h";
        };
      };
    };

    # Optional: Add direnv integration for your shell
    # Fish integration is automatic when programs.fish.enable = true
    # Bash integration is automatic when programs.bash.enable = true
  };
}
