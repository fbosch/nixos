let
  makeHeliumPackage = pkgs: pkgs.local.helium-browser;
in
{
  flake.modules.nixos.applications =
    { config
    , pkgs
    , lib
    , ...
    }:
    let
      heliumPackage = makeHeliumPackage pkgs;
      heliumWidevineSetup = heliumPackage.passthru.widevineSetup;
      heliumProfile = pkgs.replaceVars ./helium.profile {
        chromiumProfile = "${pkgs.firejail}/etc/firejail/chromium.profile";
        timeZone = config.time.timeZone;
      };
      heliumDrmProfile = pkgs.replaceVars ./helium-drm.profile {
        inherit heliumProfile;
      };
      heliumWebapps = lib.filterAttrs (name: _: lib.hasPrefix "webapp/" name) pkgs.local;
      nativeWaylandWebapps = lib.filterAttrs
        (
          _: package: package.passthru.heliumWebapp.waylandAppId != null
        )
        heliumWebapps;
      firejailedWebapps = lib.filterAttrs
        (
          _: package: package.passthru.heliumWebapp.waylandAppId == null
        )
        heliumWebapps;
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
        BackgroundModeEnabled = false;
        BuiltInDnsClientEnabled = false;
        DnsOverHttpsMode = "off";
        HardwareAccelerationModeEnabled = true;
      };
    in
    {
      environment.etc = {
        "chromium/native-messaging-hosts/com.8bit.bitwarden.json".text = bitwardenNativeMessagingHost;
        "chromium/policies/managed/helium-dns.json".text = heliumManagedPolicy;
      };

      environment.systemPackages = [ heliumWidevineSetup ] ++ builtins.attrValues nativeWaylandWebapps;

      programs.firejail.wrappedBinaries =
        lib.mapAttrs'
          (name: package: {
            name = package.meta.mainProgram or (builtins.baseNameOf name);
            value = {
              executable = lib.getExe package;
              profile = if package.passthru.heliumWebapp.enableWidevine then heliumDrmProfile else heliumProfile;
              desktop = "${package}/share/applications/${
              package.meta.mainProgram or (builtins.baseNameOf name)
            }.desktop";
            };
          })
          firejailedWebapps
        // {
          helium-browser = {
            executable = "${heliumPackage}/bin/helium-browser";
            profile = "${heliumDrmProfile}";
            desktop = "${heliumPackage}/share/applications/helium-browser.desktop";
          };
        };
    };

  flake.modules.homeManager.applications =
    { config
    , pkgs
    , ...
    }:
    let
      heliumPackage = makeHeliumPackage pkgs;
      heliumWidevineSetup = heliumPackage.passthru.widevineSetup;
    in
    {
      home.packages = [
        heliumPackage
        heliumWidevineSetup
      ];

      home.activation.heliumWidevine = config.lib.dag.entryAfter [ "writeBoundary" ] ''
        ${heliumWidevineSetup}/bin/helium-widevine-setup \
          --source ${pkgs.google-chrome}/share/google/chrome/WidevineCdm \
          --user-data-dir ${config.xdg.configHome}/net.imput.helium
      '';
    };
}
