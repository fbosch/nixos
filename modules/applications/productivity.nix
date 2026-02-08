{
  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        gimp
        pkgs.local.chromium-chatgpt
        pkgs.local.chromium-notion
        pkgs.local.chromium-protonmail
        pkgs.local.chromium-protoncalendar
      ];

      services.flatpak.packages = [ "md.obsidian.Obsidian" ];
    };
}
