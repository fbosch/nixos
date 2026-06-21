let
  makeHeliumPackage = pkgs: pkgs.local.helium-browser;
in
{
  flake.modules.nixos.applications =
    { pkgs, lib, ... }:
    let
      heliumPackage = makeHeliumPackage pkgs;
      heliumProfile = pkgs.replaceVars ./helium.profile {
        chromiumProfile = "${pkgs.firejail}/etc/firejail/chromium.profile";
      };
      heliumWebapps = lib.filterAttrs (name: _: lib.hasPrefix "webapp/" name) pkgs.local;
      bitwardenNativeMessagingHost = builtins.toJSON {
        name = "com.8bit.bitwarden";
        description = "Bitwarden desktop <-> browser bridge";
        path = "${pkgs.bitwarden-desktop}/libexec/desktop_proxy";
        type = "stdio";
        allowed_origins = [
          "chrome-extension://nngceckbapebfimnlniiiahkandclblb/"
          "chrome-extension://hccnnhgbibccigepcmlgppchkpfdophk/"
          "chrome-extension://jbkfoedolllekgbhcbcoahefnbanhhlh/"
          "chrome-extension://ccnckbpmaceehanjmeomladnmlffdjgn/"
        ];
      };
      heliumManagedPolicy = builtins.toJSON {
        BuiltInDnsClientEnabled = false;
        DnsOverHttpsMode = "off";
      };
    in
    {
      environment.etc = {
        "chromium/native-messaging-hosts/com.8bit.bitwarden.json".text = bitwardenNativeMessagingHost;
        "chromium/policies/managed/helium-dns.json".text = heliumManagedPolicy;
      };

      programs.firejail.wrappedBinaries =
        lib.mapAttrs'
          (name: package: {
            name = package.meta.mainProgram or (builtins.baseNameOf name);
            value = {
              executable = lib.getExe package;
              profile = "${heliumProfile}";
              desktop = "${package}/share/applications/${
              package.meta.mainProgram or (builtins.baseNameOf name)
            }.desktop";
            };
          })
          heliumWebapps
        // {
          helium-browser = {
            executable = "${heliumPackage}/bin/helium-browser";
            profile = "${heliumProfile}";
            desktop = "${heliumPackage}/share/applications/helium-browser.desktop";
          };
        };
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = [ (makeHeliumPackage pkgs) ];
    };
}
