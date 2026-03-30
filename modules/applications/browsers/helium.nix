{
  flake.modules.homeManager.applications =
    { pkgs
    , ...
    }:
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

      heliumPackage = pkgs.symlinkJoin {
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

      heliumWrapped = pkgs.mkBwrapper {
        imports = [ pkgs.bwrapperPresets.desktop ];
        app = {
          package = heliumPackage;
        };
      };
    in
    {
      home.packages = [ heliumWrapped ];
    };
}
