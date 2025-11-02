{
  flake.modules.nixos.virtualization = { pkgs, ... }: {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
      };
    };

    programs.virt-manager.enable = true;

    users.users.fbb.extraGroups = [ "libvirtd" ];

    environment.systemPackages = with pkgs; [
      virt-viewer
      spice
      spice-gtk
      spice-protocol
      win-virtio
      win-spice
      swtpm
      OVMFFull
    ];

    networking.firewall.trustedInterfaces = [ "virbr0" ];
  };
}
