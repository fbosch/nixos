{
  flake.modules.nixos.virtualization = { pkgs, meta, ... }: {
    # Docker
    virtualisation.docker = {
      enable = true;
      enableOnBoot = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };

    # Libvirt/QEMU
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    programs.virt-manager.enable = true;

    users.users.${meta.user.username}.extraGroups = [ "libvirtd" "docker" ];

    environment.systemPackages = with pkgs; [
      # QEMU/KVM tools
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      virtio-win
      win-spice
      swtpm
      OVMFFull
      usbredir

      # Docker tools
      docker-compose
    ];

    networking.firewall.trustedInterfaces = [ "virbr0" "docker0" ];
  };
}
