_:
{
  flake.meta = {
    user = {
      username = "fbb";
      fullName = "Frederik Bosch";
      github = { username = "fbosch"; };
    };

    dotfiles = {
      url = "https://github.com/fbosch/dotfiles";
    };

    ui = {
      emojiFont = "Apple Color Emoji";
    };

    versions = {
      homeManager = "25.05";
    };

    presets = {
      server = {
        nixos = [ "system" "users" "security" "shell" ];
        homeManager = [ "users" "dotfiles" "shell" "security" ];
      };

      desktop = {
        nixos = [ "system" "users" "vpn" "fonts" "flatpak" "security" "desktop" "development" "shell" ];
        homeManager = [ "users" "dotfiles" "fonts" "flatpak" "security" "desktop" "applications" "development" "shell" "services" ];
      };

      devServer = {
        nixos = [ "system" "users" "vpn" "security" "development" "shell" ];
        homeManager = [ "users" "dotfiles" "shell" "development" "security" ];
      };
    };
  };
}
