let
  makeHeliumPackage =
    pkgs:
    let
      heliumExtensionForcelist = [
        "nngceckbapebfimnlniiiahkandclblb;https://clients2.google.com/service/update2/crx"
        "mendokngpagmkejfpmeellpppjgbpdaj;https://clients2.google.com/service/update2/crx"
      ];

      heliumManagedPolicy = pkgs.writeText "helium-managed-policy.json" (
        builtins.toJSON {
          ExtensionInstallForcelist = heliumExtensionForcelist;
        }
      );

      heliumPolicyTree = pkgs.runCommand "helium-policy-tree" { } ''
        install -Dm444 ${heliumManagedPolicy} \
          "$out/share/chromium/policies/managed/extensions.json"
      '';
    in
    pkgs.symlinkJoin {
      pname = "helium-browser";
      inherit (pkgs.local.helium-browser) version;
      paths = [
        pkgs.local.helium-browser
        heliumPolicyTree
      ];
      inherit (pkgs.local.helium-browser) meta;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram "$out/bin/helium-browser" \
          --set CHROME_POLICY_FILES_DIR "$out/share/chromium/policies"
      '';
    };
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
    in
    {
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
