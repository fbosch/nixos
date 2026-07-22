{ startupPolicy }:
let
  nixosConfig = {
    services.startupPolicy.quadletUnitSettings."example.service" = {
      target = "startup-policy-app-example.target";
      slice = "startup-policy-background.slice";
    };
  };
in
{
  testRegisteredQuadletReturnsSettings = {
    expr = startupPolicy.quadlet nixosConfig "example.service";
    expected = {
      target = "startup-policy-app-example.target";
      slice = "startup-policy-background.slice";
    };
  };

  testUnregisteredQuadletFails = {
    expr = (builtins.tryEval (startupPolicy.quadlet nixosConfig "missing.service")).success;
    expected = false;
  };
}
