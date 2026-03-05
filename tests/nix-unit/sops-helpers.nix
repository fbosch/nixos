{ sopsHelpers }:
let
  secretsFile = builtins.toFile "secrets.yaml" "";
in
{
  testRootOnlyPermissions = {
    expr = sopsHelpers.rootOnly;
    expected = {
      mode = "0400";
    };
  };

  testWheelReadablePermissions = {
    expr = sopsHelpers.wheelReadable;
    expected = {
      mode = "0440";
      group = "wheel";
    };
  };

  testWorldReadablePermissions = {
    expr = sopsHelpers.worldReadable;
    expected = {
      mode = "0444";
    };
  };

  testMkSecretMergesOptions = {
    expr = sopsHelpers.mkSecret secretsFile {
      mode = "0440";
      group = "wheel";
    };
    expected = {
      sopsFile = secretsFile;
      mode = "0440";
      group = "wheel";
    };
  };

  testMkSecretsBuildsNamedSet = {
    expr = sopsHelpers.mkSecrets secretsFile [ "api-key" "db-pass" ];
    expected = {
      api-key = {
        sopsFile = secretsFile;
      };
      db-pass = {
        sopsFile = secretsFile;
      };
    };
  };

  testMkSecretsWithOptsAppliesDefaults = {
    expr = sopsHelpers.mkSecretsWithOpts secretsFile
      {
        mode = "0440";
        group = "wheel";
      } [ "service-token" ];
    expected = {
      service-token = {
        sopsFile = secretsFile;
        mode = "0440";
        group = "wheel";
      };
    };
  };
}
