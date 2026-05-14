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
    { pkgs, ... }:
    let
      heliumPackage = makeHeliumPackage pkgs;
      heliumProfile = pkgs.replaceVars ./helium.profile {
        chromiumProfile = "${pkgs.firejail}/etc/firejail/chromium.profile";
      };
    in
    {
      programs.firejail.wrappedBinaries.helium-browser = {
        executable = "${heliumPackage}/bin/helium-browser";
        profile = "${heliumProfile}";
        desktop = "${heliumPackage}/share/applications/helium-browser.desktop";
      };
    };

  flake.modules.homeManager.applications =
    { pkgs, ... }:
    {
      home.packages = [ (makeHeliumPackage pkgs) ];
    };
}
