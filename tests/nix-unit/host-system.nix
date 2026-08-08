{ hostSystem }:
let
  normalizes = system: hostSystem { inherit system; };
  fails = system: (builtins.tryEval (normalizes system)).success;
in
{
  testX86Linux = {
    expr = normalizes "x86_64-linux";
    expected = "x86_64-linux";
  };

  testAarch64Linux = {
    expr = normalizes "aarch64-linux";
    expected = "aarch64-linux";
  };

  testAarch64Darwin = {
    expr = normalizes "aarch64-darwin";
    expected = "aarch64-darwin";
  };

  testX86Darwin = {
    expr = normalizes "x86_64-darwin";
    expected = "x86_64-darwin";
  };

  testMalformedSystemFails = {
    expr = fails "not-a-system";
    expected = false;
  };

  testNoncanonicalSystemFails = {
    expr = fails "arm64-darwin";
    expected = false;
  };

  testMissingSystemFails = {
    expr = fails null;
    expected = false;
  };

  testUnsupportedSystemFails = {
    expr = fails "x86_64-windows";
    expected = false;
  };

  testNixOSDarwinMismatchFails = {
    expr =
      (builtins.tryEval (hostSystem {
        system = "aarch64-darwin";
        hostName = "test";
        hostType = "nixos";
      })).success;
    expected = false;
  };

  testDarwinLinuxMismatchFails = {
    expr =
      (builtins.tryEval (hostSystem {
        system = "x86_64-linux";
        hostName = "test";
        hostType = "darwin";
      })).success;
    expected = false;
  };
}
