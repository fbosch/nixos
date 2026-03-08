{ config, ... }:
{
  flake.modules.nixos."virtualization/libvirt" =
    { lib, pkgs, ... }:
    let
      initEncryptionSecretScript = pkgs.writeShellApplication {
        name = "virt-secret-init-encryption";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.systemd
        ];
        text = builtins.readFile ./scripts/virt-secret-init-encryption.sh;
      };
    in
    {
      # Libvirt/QEMU
      virtualisation.libvirtd = {
        enable = true;
        qemu = {
          package = pkgs.qemu_kvm;
          runAsRoot = false;
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

      systemd.services.virt-secret-init-encryption.serviceConfig.ExecStart = lib.mkForce [
        ""
        "${initEncryptionSecretScript}/bin/virt-secret-init-encryption"
      ];
    };
}
