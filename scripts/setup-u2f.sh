#!/usr/bin/env bash

set -euo pipefail

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
	cat <<'EOF'
Usage: ./scripts/setup-u2f.sh [pam://rp-id]

Registers one U2F credential for the current user and writes it to:
  ~/.config/Yubico/u2f_keys

If no relying party is provided, defaults to pam://$(hostname -s)
EOF
	exit 0
fi

if [[ ${EUID} -eq 0 ]]; then
	printf 'Run as regular user, not root.\n' >&2
	exit 1
fi

if ! command -v pamu2fcfg >/dev/null 2>&1; then
	printf 'Missing pamu2fcfg. Rebuild host with pam_u2f package first.\n' >&2
	exit 1
fi

if ! command -v fido2-token >/dev/null 2>&1; then
	printf 'Missing fido2-token. Rebuild host with libfido2 package first.\n' >&2
	exit 1
fi

if [[ -z "$(fido2-token -L 2>/dev/null || true)" ]]; then
	printf 'No FIDO2 token detected. Insert key, then retry.\n' >&2
	exit 1
fi

rp="${1:-pam://$(hostname -s)}"
user_name="${USER}"
auth_dir="${HOME}/.config/Yubico"
auth_file="${auth_dir}/u2f_keys"

mkdir -p "${auth_dir}"
chmod 700 "${auth_dir}"

printf 'Using relying party: %s\n' "${rp}"
printf 'Touch your security key when prompted...\n'

new_entry="$(pamu2fcfg -u "${user_name}" -o "${rp}" -i "${rp}")"

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

if [[ -f ${auth_file} ]]; then
	cp "${auth_file}" "${auth_file}.bak.$(date +%Y%m%d%H%M%S)"
	awk -v user="${user_name}" -F: '$1 != user' "${auth_file}" >"${tmp_file}"
fi

printf '%s\n' "${new_entry}" >>"${tmp_file}"
mv "${tmp_file}" "${auth_file}"
chmod 600 "${auth_file}"

printf 'Wrote %s\n' "${auth_file}"
printf 'Test with: sudo -k && sudo true\n'
