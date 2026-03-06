{ lib }:
let
  findDuplicates =
    portList:
    let
      grouped = builtins.groupBy (item: toString item.port) portList;
    in
    lib.filterAttrs (_port: items: (lib.length items) > 1) grouped;
in
{
  testNoDuplicatesReturnsEmpty = {
    expr = findDuplicates [
      {
        service = "foo";
        port = 8080;
      }
      {
        service = "bar";
        port = 8081;
      }
    ];
    expected = { };
  };

  testSingleDuplicateDetected = {
    expr = findDuplicates [
      {
        service = "foo";
        port = 8080;
      }
      {
        service = "bar";
        port = 8080;
      }
    ];
    expected = {
      "8080" = [
        {
          service = "foo";
          port = 8080;
        }
        {
          service = "bar";
          port = 8080;
        }
      ];
    };
  };

  testThreeWayConflictDetected = {
    expr = findDuplicates [
      {
        service = "a";
        port = 53;
      }
      {
        service = "b";
        port = 53;
      }
      {
        service = "c";
        port = 53;
      }
    ];
    expected = {
      "53" = [
        {
          service = "a";
          port = 53;
        }
        {
          service = "b";
          port = 53;
        }
        {
          service = "c";
          port = 53;
        }
      ];
    };
  };

  testMixedPortsOnlyReturnsDuplicates = {
    expr = findDuplicates [
      {
        service = "foo";
        port = 8080;
      }
      {
        service = "bar";
        port = 8080;
      }
      {
        service = "baz";
        port = 9090;
      }
    ];
    expected = {
      "8080" = [
        {
          service = "foo";
          port = 8080;
        }
        {
          service = "bar";
          port = 8080;
        }
      ];
    };
  };

  testEmptyListReturnsEmpty = {
    expr = findDuplicates [ ];
    expected = { };
  };
}
