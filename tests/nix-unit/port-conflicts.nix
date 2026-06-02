{ portConflicts }:
{
  testNoDuplicatesReturnsEmptyReport = {
    expr = portConflicts.report [
      {
        service = "foo";
        tcpPorts = [ 8080 ];
      }
      {
        service = "bar";
        tcpPorts = [ 8081 ];
      }
    ];
    expected = {
      tcp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      udp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      hasConflicts = false;
    };
  };

  testSingleTcpDuplicateDetected = {
    expr = portConflicts.report [
      {
        service = "foo";
        tcpPorts = [ 8080 ];
      }
      {
        service = "bar";
        tcpPorts = [ 8080 ];
      }
    ];
    expected = {
      tcp = {
        duplicates = {
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
        hasConflicts = true;
        message = "  TCP port 8080: foo, bar";
      };
      udp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      hasConflicts = true;
    };
  };

  testSingleUdpDuplicateDetected = {
    expr = portConflicts.report [
      {
        service = "foo";
        udpPorts = [ 53 ];
      }
      {
        service = "bar";
        udpPorts = [ 53 ];
      }
    ];
    expected = {
      tcp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      udp = {
        duplicates = {
          "53" = [
            {
              service = "foo";
              port = 53;
            }
            {
              service = "bar";
              port = 53;
            }
          ];
        };
        hasConflicts = true;
        message = "  UDP port 53: foo, bar";
      };
      hasConflicts = true;
    };
  };

  testThreeWayTcpConflictDetected = {
    expr =
      (portConflicts.report [
        {
          service = "a";
          tcpPorts = [ 53 ];
        }
        {
          service = "b";
          tcpPorts = [ 53 ];
        }
        {
          service = "c";
          tcpPorts = [ 53 ];
        }
      ]).tcp.duplicates;
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
    expr =
      (portConflicts.report [
        {
          service = "foo";
          tcpPorts = [ 8080 ];
        }
        {
          service = "bar";
          tcpPorts = [ 8080 ];
        }
        {
          service = "baz";
          tcpPorts = [ 9090 ];
        }
      ]).tcp.duplicates;
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
    expr = portConflicts.report [ ];
    expected = {
      tcp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      udp = {
        duplicates = { };
        hasConflicts = false;
        message = "";
      };
      hasConflicts = false;
    };
  };
}
