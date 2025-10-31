{
  flake.modules.nixos.windows.winapps = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [ freerdp virt-manager ];

    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = false;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [ pkgs.OVMFFull.fd ];
        };
      };
    };
  };

  flake.modules.homeManager.windows.winapps = { pkgs, ... }: {
    home.packages = with pkgs; [ freerdp ];

    home.file.".config/winapps/winapps.conf".text = ''
      RDP_USER="User"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_SCALE=100
      RDP_FLAGS="/sound /microphone /audio-mode:0"
      MULTIMON="false"
      DEBUG="false"
    '';
  };
}
