{
  flake.modules.homeManager.applications = { pkgs, ... }: {
    home.packages = with pkgs; [
      hardinfo2
      local.chromium-realforce # Realforce keyboard configuration tool
    ];
  };
}
