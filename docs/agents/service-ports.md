# Service Ports

Current service port assignments used by the `rvn-srv` host.

Declared exposed ports for `rvn-srv` are linted against this document.

## Port map

| Service                   | Port(s)                        | Notes                        |
| ------------------------- | ------------------------------ | ---------------------------- |
| atuin                     | `8086/tcp`                     | Shell history sync server    |
| atticd                    | `8081/tcp`                     | Default atticd API port      |
| home-assistant            | `8123/tcp`                     | Home automation web UI       |
| freshrss                  | `8084/tcp`                     | RSS reader web interface     |
| glance-container (nginx)  | `8080/tcp`                     | LAN web UI and API router    |
| glance-container          | `8083/tcp`                     | Loopback Glance backend      |
| pihole-container          | `8082/tcp`, `53/tcp`, `53/udp` | Web UI + DNS                 |
| dozzle                    | `8090/tcp`                     | Container log viewer         |
| gluetun-container         | `8889/tcp`, `8000/tcp`         | Proxy + control API          |
| tinyproxy                 | `8888/tcp`                     | Local/TS proxy               |
| uptime-kuma               | `3001/tcp`                     | Monitoring web UI            |
| prowlarr                  | `9696/tcp`                     | *arr indexer manager         |
| glances                   | `61208/tcp`                    | Monitoring web UI            |
| tailscale-relay           | `40000/udp`                    | DERP relay server port       |
| helium-services-container | `8100/tcp`                     | Helium service HTTP port     |
| linkwarden-container      | `3100/tcp`                     | Web UI                       |
| komodo                    | `9120/tcp`, `8120/tcp`         | Core UI + periphery          |
| rdtclient                 | `6500/tcp`                     | Web UI/API                   |
| flaresolverr-container    | `8191/tcp`                     | FlareSolverr API             |
| speedtest-tracker         | `8085/tcp`                     | Web UI                       |
| termix-container          | `7310/tcp`                     | Container web port           |
| priceghost-container      | `8089/tcp`                     | Price tracking web UI        |
| glance-shared-todo        | `8091/tcp`, `8092/tcp`         | Loopback API + LAN MCP       |
| plex (nginx)              | `32402/tcp`                    | Reverse proxy port           |
| onwatch-container         | `9211/tcp`                     | API quota tracker dashboard  |
| rsshub-container          | `1200/tcp`                     | RSS feed aggregation service |

## Update workflow

1. Before assigning a new port, search for conflicts in `modules/**/*.nix`.
2. Keep this file updated when adding or changing service ports.
3. For service modules, also update `services.exposedPorts` declarations used by `validation/container-port-conflicts`.
