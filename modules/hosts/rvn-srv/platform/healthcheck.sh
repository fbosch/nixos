#!/usr/bin/env bash

set -euo pipefail

failures=0
warnings=0
host_address="192.168.1.46"

section() {
	printf '\n== %s ==\n' "$1"
}

pass() {
	printf 'OK   %s\n' "$1"
}

warn() {
	warnings=$((warnings + 1))
	printf 'WARN %s\n' "$1"
}

fail() {
	failures=$((failures + 1))
	printf 'FAIL %s\n' "$1"
}

check_memory() {
	local mem_available_kib swap_total_kib swap_free_kib swap_used_percent

	mem_available_kib="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
	swap_total_kib="$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)"
	swap_free_kib="$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)"

	if [ "$mem_available_kib" -lt 1048576 ]; then
		fail "available memory below 1 GiB ($(numfmt --from-unit=1024 --to=iec "$mem_available_kib"))"
	elif [ "$mem_available_kib" -lt 2097152 ]; then
		warn "available memory below 2 GiB ($(numfmt --from-unit=1024 --to=iec "$mem_available_kib"))"
	else
		pass "available memory $(numfmt --from-unit=1024 --to=iec "$mem_available_kib")"
	fi

	if [ "$swap_total_kib" -gt 0 ]; then
		swap_used_percent=$(((swap_total_kib - swap_free_kib) * 100 / swap_total_kib))
		if [ "$swap_used_percent" -gt 50 ]; then
			fail "swap usage ${swap_used_percent}%"
		elif [ "$swap_used_percent" -gt 25 ]; then
			warn "swap usage ${swap_used_percent}%"
		else
			pass "swap usage ${swap_used_percent}%"
		fi
	else
		warn "swap is not configured"
	fi
}

check_disk() {
	local path="$1"
	local usage

	if [ ! -e "$path" ]; then
		fail "$path does not exist"
		return
	fi

	usage="$(df -P "$path" | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"

	if [ "$usage" -ge 95 ]; then
		fail "$path filesystem usage ${usage}%"
	elif [ "$usage" -ge 85 ]; then
		warn "$path filesystem usage ${usage}%"
	else
		pass "$path filesystem usage ${usage}%"
	fi
}

check_failed_units() {
	local failed_units

	failed_units="$(systemctl --failed --no-legend --plain || true)"
	if [ -n "$failed_units" ]; then
		fail "systemd has failed units"
		printf '%s\n' "$failed_units"
	else
		pass "no failed systemd units"
	fi
}

check_unit_active() {
	local unit="$1"

	if systemctl is-active --quiet "$unit"; then
		pass "$unit active"
	elif systemctl list-unit-files --full --no-legend "$unit" | grep -q .; then
		fail "$unit not active ($(systemctl is-active "$unit" || true))"
	else
		warn "$unit is not installed"
	fi
}

check_path_mounted() {
	local path="$1"

	if [ ! -e "$path" ]; then
		fail "$path does not exist"
		return
	fi

	if findmnt --mountpoint "$path" >/dev/null; then
		pass "$path is a mountpoint"
	else
		fail "$path is not a mountpoint"
	fi
}

check_tcp_port() {
	local name="$1"
	local host="$2"
	local port="$3"

	if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
		pass "$name reachable at $host:$port"
	else
		fail "$name not reachable at $host:$port"
	fi
}

check_http_status() {
	local name="$1"
	local url="$2"
	local status

	status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' --max-time 5 "$url" 2>/dev/null || true)"
	case "$status" in
	2* | 3*)
		pass "$name HTTP ${status} at $url"
		;;
	"")
		fail "$name did not respond at $url"
		;;
	*)
		fail "$name HTTP ${status} at $url"
		;;
	esac
}

check_env_file() {
	local name="$1"
	local path="$2"

	if [ ! -e "$path" ]; then
		fail "$name env file missing: $path"
		return
	fi

	if [ -r "$path" ]; then
		pass "$name env file readable"
	else
		warn "$name env file exists but is not readable by $(id -un)"
	fi
}

check_meilisearch_api() {
	local env_file="/run/secrets/rendered/linkwarden-env"
	local node_script

	if [ "$EUID" -ne 0 ]; then
		warn "Meilisearch API check skipped; run as root to inspect root-owned containers"
		return
	fi

	if [ ! -r "$env_file" ]; then
		warn "Meilisearch API check skipped; cannot read $env_file"
		return
	fi

	set -a
	# shellcheck disable=SC1090
	. "$env_file"
	set +a

	if [ -z "${MEILI_MASTER_KEY:-}" ]; then
		fail "MEILI_MASTER_KEY missing from $env_file"
		return
	fi

	if ! podman ps --format '{{.Names}}' | grep -Fxq linkwarden; then
		fail "Meilisearch API check skipped; linkwarden container is not running"
		return
	fi

	# shellcheck disable=SC2016
	node_script='const http=require("http"); const key=process.env.MEILI_MASTER_KEY; const req=http.request({host:"linkwarden-meilisearch",port:7700,path:"/health",headers:{Authorization:`Bearer ${key}`},timeout:5000},res=>process.exit(res.statusCode===200?0:1)); req.on("error",()=>process.exit(1)); req.on("timeout",()=>{req.destroy(); process.exit(1);}); req.end();'

	if podman exec linkwarden node -e "$node_script" >/dev/null 2>&1; then
		pass "Meilisearch authenticated /health HTTP 200"
	else
		fail "Meilisearch authenticated /health failed"
	fi
}

check_linkwarden_postgres() {
	if [ "$EUID" -ne 0 ]; then
		warn "Linkwarden PostgreSQL check skipped; run as root to inspect root-owned containers"
		return
	fi

	if ! podman ps --format '{{.Names}}' | grep -Fxq linkwarden-postgres; then
		fail "linkwarden-postgres container is not running"
		return
	fi

	if podman exec linkwarden-postgres pg_isready -U postgres >/dev/null 2>&1; then
		pass "Linkwarden PostgreSQL accepts connections"
	else
		fail "Linkwarden PostgreSQL pg_isready failed"
	fi
}

check_podman() {
	local bad_containers unhealthy

	if ! systemctl is-active --quiet podman.service; then
		fail "podman.service is not active"
		return
	fi

	if [ "$EUID" -ne 0 ]; then
		warn "Podman container checks are limited; run as root to inspect system containers"
	fi

	bad_containers="$(podman ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null |
		awk '$0 ~ /Exited|Restarting|Created|Dead/ && $1 !~ /^linkwarden-meilisearch-(migrate-old|import-new)$/ { print }')"
	if [ -n "$bad_containers" ]; then
		fail "Podman containers are not running cleanly"
		printf '%s\n' "$bad_containers"
	else
		pass "no exited/restarting Podman containers"
	fi

	unhealthy="$(podman ps --filter health=unhealthy --format '{{.Names}}' 2>/dev/null || true)"
	if [ -n "$unhealthy" ]; then
		fail "unhealthy Podman containers"
		printf '%s\n' "$unhealthy"
	else
		pass "no unhealthy running Podman containers"
	fi
}

check_recent_oom() {
	local oom_logs

	if ! journalctl -k --since '-1 hour' --no-pager >/dev/null 2>&1; then
		warn "recent OOM check skipped; journal is not readable by $(id -un)"
		return
	fi

	oom_logs="$(journalctl -k --since '-1 hour' --no-pager 2>/dev/null |
		grep -Ei 'out of memory|oom-kill|killed process' || true)"
	if [ -n "$oom_logs" ]; then
		fail "kernel reported OOM activity in the last hour"
		printf '%s\n' "$oom_logs"
	else
		pass "no kernel OOM activity in the last hour"
	fi
}

printf 'rvn-srv healthcheck on %s at %s\n' "$(hostname)" "$(date --iso-8601=seconds)"

section "System Pressure"
check_memory
check_disk /
check_disk /var/lib
check_recent_oom

section "Systemd"
check_failed_units
for unit in \
	nginx.service \
	podman.service \
	postgresql.service \
	tailscaled.service \
	home-assistant.service \
	plex.service \
	uptime-kuma.service \
	gluetun.service \
	pihole.service \
	linkwarden-postgres.service \
	linkwarden-meilisearch.service \
	linkwarden.service; do
	check_unit_active "$unit"
done

section "Podman"
check_podman
check_linkwarden_postgres

section "Secrets"
check_env_file "Linkwarden" /run/secrets/rendered/linkwarden-env
check_env_file "Gluetun" /run/secrets/rendered/gluetun-env
check_env_file "Speedtest Tracker" /run/secrets/rendered/speedtest-tracker-env

section "NAS Paths"
check_path_mounted /mnt/nas/downloads
check_path_mounted /mnt/nas/video
check_disk /mnt/nas/downloads
check_disk /mnt/nas/video

section "Local Ports"
check_tcp_port "uptime-kuma" 127.0.0.1 3001
check_tcp_port "linkwarden" 127.0.0.1 3100
check_tcp_port "pihole" "$host_address" 8082
check_tcp_port "glances" 127.0.0.1 61208

section "HTTP APIs"
check_http_status "uptime-kuma" http://127.0.0.1:3001/
check_http_status "linkwarden" http://127.0.0.1:3100/
check_http_status "pihole" "http://${host_address}:8082/admin/"
check_http_status "glances" http://127.0.0.1:61208/
check_meilisearch_api

section "Summary"
if [ "$failures" -gt 0 ]; then
	printf 'FAIL %s failure(s), %s warning(s)\n' "$failures" "$warnings"
	exit 1
fi

if [ "$warnings" -gt 0 ]; then
	printf 'WARN 0 failure(s), %s warning(s)\n' "$warnings"
	exit 0
fi

printf 'OK   all checks passed\n'
