{ config, ... }:
{
  flake.modules.nixos."virtualization/libvirt" =
    { pkgs, ... }:
    {
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

      users.users.${config.flake.meta.user.username}.extraGroups = [ "libvirtd" ];

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
      ];

      networking.firewall.trustedInterfaces = [ "virbr0" ];
    };
}
