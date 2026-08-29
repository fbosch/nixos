{ config, inputs, ... }:
{
  flake.modules.nixos = {
    "virtualization/libvirt" =
      { lib, pkgs, ... }:
      let
        initEncryptionSecretScript = pkgs.writeShellApplication {
          name = "virt-secret-init-encryption";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.systemd
          ];
          text = ''
            readonly secrets_encryption_key_path="/var/lib/libvirt/secrets/secrets-encryption-key"
            umask 0077
            dd if=/dev/random status=none bs=32 count=1 |
              systemd-creds encrypt --name=secrets-encryption-key - "$secrets_encryption_key_path"
          '';
        };
      in
      {
        # Libvirt/QEMU
        virtualisation.libvirtd = {
          enable = true;
          qemu = {
            package = pkgs.qemu_kvm;
            vhostUserPackages = [ pkgs.virtiofsd ];
            runAsRoot = true;
            verbatimConfig = ''
              namespaces = []

              cgroup_device_acl = [
                "/dev/null", "/dev/full", "/dev/zero",
                "/dev/random", "/dev/urandom",
                "/dev/ptmx", "/dev/kvm", "/dev/kqemu",
                "/dev/rtc", "/dev/hpet", "/dev/sev",
                "/dev/vfio/vfio", "/dev/net/tun",

                "/dev/dri/renderD128",
                "/dev/nvidia0", "/dev/nvidiactl",
                "/dev/nvidia-modeset", "/dev/nvidia-uvm",
                "/dev/nvidia-uvm-tools"
              ]
            '';
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

    preservation =
      { config, lib, ... }:
      {
        config = lib.mkMerge [
          (lib.mkIf config.virtualisation.libvirtd.enable {
            preservation.preserveAt."/persist".directories = [
              {
                directory = "/var/lib/libvirt";
                mode = "0755";
              }
            ];
          })
          (lib.mkIf config.virtualisation.libvirtd.qemu.swtpm.enable {
            preservation.preserveAt."/persist".directories = [
              {
                directory = "/var/lib/swtpm-localca";
                mode = "0750";
              }
            ];
          })
        ];
      };
  };

  perSystem =
    { lib, system, ... }:
    let
      persistencePaths =
        { libvirt ? false
        , swtpm ? false
        ,
        }:
        let
          evaluated = inputs.nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              inputs.preservation.nixosModules.preservation
              config.flake.modules.nixos.preservation
              {
                system.stateVersion = "25.05";
                virtualisation.libvirtd = {
                  enable = libvirt || swtpm;
                  qemu.swtpm.enable = swtpm;
                };
              }
            ];
          };
        in
        lib.sortOn (value: value.directory) (
          map
            (value: {
              inherit (value) directory mode;
            })
            (evaluated.config.preservation.preserveAt."/persist".directories or [ ])
        );
    in
    {
      nix-unit.tests.libvirtPreservation = lib.optionalAttrs (system == "x86_64-linux") {
        testDisabledLibvirtContributesNothing = {
          expr = persistencePaths { };
          expected = [ ];
        };

        testLibvirtOwnsRuntimeState = {
          expr = persistencePaths { libvirt = true; };
          expected = [
            {
              directory = "/var/lib/libvirt";
              mode = "0755";
            }
          ];
        };

        testSwtpmOwnsLocalCertificateAuthority = {
          expr = persistencePaths {
            libvirt = true;
            swtpm = true;
          };
          expected = [
            {
              directory = "/var/lib/libvirt";
              mode = "0755";
            }
            {
              directory = "/var/lib/swtpm-localca";
              mode = "0750";
            }
          ];
        };
      };
    };
}
