# Service Ports

Current service port assignments used by the `rvn-srv` host.

Declared exposed ports for `rvn-srv` are linted against this document.

## Port map

| Service                   | Port(s)                        | Notes                        |
| ------------------------- | ------------------------------ | ---------------------------- |
| atuin                     | `8086/tcp`                     | Shell history sync server    |
| atticd                    | `8081/tcp`                     | Default atticd API port      |
| glance-container          | `8080/tcp`                     | Container web UI             |
| glance-container (nginx)  | `8083/tcp`                     | Reverse proxy port           |
| pihole-container          | `8082/tcp`, `53/tcp`, `53/udp` | Web UI + DNS                 |
| dozzle                    | `8090/tcp`                     | Container log viewer         |
| gluetun-container         | `8889/tcp`, `8000/tcp`         | Proxy + control API          |
| tinyproxy                 | `8888/tcp`                     | Local/TS proxy               |
| uptime-kuma               | `3001/tcp`                     | Monitoring web UI            |
| prowlarr                  | `9696/tcp`                     | *arr indexer manager         |
| glances                   | `61208/tcp`                    | Monitoring web UI            |
| tailscale-relay           | `40000/udp`                    | DERP relay server port       |
| helium-services-container | `8100/tcp`                     | Helium service HTTP port     |
| openmemory-container      | `8380/tcp`, `3380/tcp`         | API server + dashboard       |
| linkwarden-container      | `3100/tcp`                     | Web UI                       |
| komodo                    | `9120/tcp`, `8120/tcp`         | Core UI + periphery          |
| rdtclient                 | `6500/tcp`                     | Web UI/API                   |
| flaresolverr-container    | `8191/tcp`                     | FlareSolverr API             |
| speedtest-tracker         | `8085/tcp`                     | Web UI                       |
| termix-container          | `7310/tcp`                     | Container web port           |
| priceghost-container      | `8089/tcp`                     | Price tracking web UI        |
| plex (nginx)              | `32402/tcp`                    | Reverse proxy port           |
| onwatch-container         | `9211/tcp`                     | API quota tracker dashboard  |
| rsshub-container          | `1200/tcp`                     | RSS feed aggregation service |

## Update workflow

1

- Before assigning a new port, search for conflicts in `modules/**/*.nix`.
- Keep this file updated when adding/changing service ports.
- For service modules, also update `services.exposedPorts` declarations used by `validation/container-port-conflicts`.
