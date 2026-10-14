{
  flake.modules.nixos.applications =
    { pkgs, ... }:
    let
      googleChrome = pkgs.google-chrome.overrideAttrs (previous: {
        postFixup = (previous.postFixup or "") + ''
          ln -sf /run/wrappers/bin/chrome-sandbox \
            "$out/share/google/chrome/chrome-sandbox"
        '';
      });
    in
    {
      environment.systemPackages = [ googleChrome ];

      # The immutable store copy cannot be setuid; Chrome expects this helper beside its binaries.
      security.wrappers.chrome-sandbox = {
        source = "${pkgs.google-chrome}/share/google/chrome/chrome-sandbox";
        owner = "root";
        group = "root";
        setuid = true;
      };
    };
}
