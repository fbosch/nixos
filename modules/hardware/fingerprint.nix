{
  # Kensington VeriMark is a FIDO2 security key, not a system fingerprint reader
  # It works for passkeys/WebAuthn in browsers, not for OS-level authentication
  flake.modules.nixos."hardware/fingerprint" =
    { pkgs, ... }:
    {
      # Note: fprintd won't detect VeriMark - it's a standalone FIDO2 device
      # Keeping this disabled unless you have an actual integrated fingerprint reader
      # services.fprintd.enable = false;

      # Add FIDO2 tools for managing the VeriMark security key
      environment.systemPackages = with pkgs; [
        libfido2 # FIDO2 library and tools (fido2-token, fido2-cred, etc.)
      ];

      # Ensure user has access to the FIDO2 device
      # The udev rules from security.nix (libfido2) handle this
    };
}
