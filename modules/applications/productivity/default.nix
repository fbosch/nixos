{
  flake.modules.nixos.applications = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      vscodium
      gimp
      local."webapp/chatgpt"
      local."webapp/notion"
      local."webapp/icloud-notes"
      local."webapp/protonmail"
      local."webapp/protoncalendar"
      local."webapp/linear"
      local."webapp/figma"
      local."webapp/apple-maps"
    ];
  };

  flake.modules.homeManager.applications =
    { lib, ... }:
    {
      services.flatpak.packages = [
        "md.obsidian.Obsidian"
        "io.github.efogdev.mpris-timer"
        "io.github.tanaybhomia.Whisp"
      ];
    };
}
