# Service Ports

Current service port assignments used by the `rvn-srv` host.

## Port map

| Service | Port(s) | Notes |
| --- | --- | --- |
| atuin | `8086/tcp` | Shell history sync server |
| atticd | `8081/tcp` | Default atticd API port |
| glance-container | `8080/tcp` | Container web UI |
| glance-container (nginx) | `8083/tcp` | Reverse proxy port |
| pihole-container | `8082/tcp`, `53/tcp`, `53/udp` | Web UI + DNS |
| dozzle | `8090/tcp` | Container log viewer |
| gluetun-container | `8889/tcp`, `8000/tcp` | Proxy + control API |
| tinyproxy | `8888/tcp` | Local/TS proxy |
| redlib-container | `8282/tcp` | App port |
| redlib-container (nginx) | `8283/tcp` | Reverse proxy port |
| helium-services-container | `8100/tcp` | Helium service HTTP port |
| linkwarden-container | `3100/tcp` | Web UI |
| rdtclient | `6500/tcp` | Web UI/API |
| speedtest-tracker | `8085/tcp` | Web UI |
| termix-container | `7310/tcp` | Container web port |
| plex (nginx) | `32402/tcp` | Reverse proxy port |

## Update workflow

- Before assigning a new port, search for conflicts in `modules/**/*.nix`.
- Keep this file updated when adding/changing service ports.
- For container modules, also update `services.containerPorts` declarations used by `validation/container-port-conflicts`.
