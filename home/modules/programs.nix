{ pkgs, config, ... }: {
  nix.settings = {
    builders-use-substitutes = true;
    extra-substituters = [ "https://anyrun.cachix.org" ];
    extra-trusted-public-keys =
      [ "anyrun.cachix.org-1:pqBobmOjI7nKlsUMV25u9QHa9btJK65/C8vnO3p346s=" ];
  };

  programs.bash = {
    enable = true;
    initExtra = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then 
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  programs.git = {
    enable = true;
    extraConfig.credential.helper = "manager";
    extraConfig.credential."https://github.com".username = "fbosch";
    extraConfig.credential.credentialStore = "gpg";
  };

  programs.fzf.enable = true;
  programs.bat.enable = true;
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    pinentry.package = pkgs.pinentry-curses;
    enableSshSupport = true;
  };

  programs.neovim.enable = true;
  programs.zen-browser.enable = true;
  programs.anyrun = {
    enable = true;
    config = {
      plugins = [
        "${pkgs.anyrun}/lib/libapplications.so"
        "${pkgs.anyrun}/lib/libsymbols.so"
      ];
    };
  };

  services.swaync = {
    enable = true;
    package = pkgs.swaynotificationcenter;
  };

  programs.waybar-nixos-updates = {
    enable = true;
    updateInterval = 3600; # every hour
    nixosConfigPath = "~/nixos";
    skipAfterBoot = true;
    gracePeriod = 60;
    updateLockFile = true;
  };
}
