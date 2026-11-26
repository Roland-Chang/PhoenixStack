#!/usr/bin/env bash
# =============================================================================
# unifi-export.sh — read-only export of the UDM's network and firewall settings
#
# Saves one JSON file per area (networks, firewall zones and policies, port
# forwards, switch port profiles, local DNS, clients) so the configuration can be
# reviewed against guests/README.md ("UDM rules"). It only reads: every request
# after the login is a GET, and it logs out at the end.
#
# Login: a UniFi OS local admin with the Network "View Only" role (local access
# only, so no UI.com SSO or MFA prompt). Its username and password are read from
# 1Password at run time, never stored or printed:
#   op://infrastructure/UniFi read-only export/username
#   op://infrastructure/UniFi read-only export/password
#
# Secrets are removed before anything is written: UniFi names secret fields
# with an "x_" prefix (WiFi passphrases, VPN keys, device auth keys), and every
# such field is deleted at any depth. WiFi settings (wlanconf) aren't exported.
#
# Usage:
#   OP_ACCOUNT=<account id> tools/unifi-export.sh [--host 10.101.0.254] [--out DIR] [--insecure]
#
#   --insecure  accept the UDM's self-signed certificate (curl -k). Needed unless the
#               UDM has a certificate your workstation trusts. Only use it on your own LAN/VPN.
#
# Output (default): ~/phoenix-unifi-export/<timestamp>/  — outside the repo, which is public.
# =============================================================================
set -Eeuo pipefail
umask 077

HOST="10.101.0.254"
SITE="default"
OUT=""
INSECURE="no"
OP_ITEM="op://infrastructure/UniFi read-only export"

while [[ $# -gt 0 ]]; do
  case $1 in
    --host)     HOST=${2:?}; shift 2 ;;
    --site)     SITE=${2:?}; shift 2 ;;
    --out)      OUT=${2:?}; shift 2 ;;
    --insecure) INSECURE="yes"; shift ;;
    -h|--help)  sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit 0 ;;
    *)          echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

: "${OP_ACCOUNT:?set OP_ACCOUNT to the PhoenixStack 1Password account (the default 1Password account has no infrastructure vault)}"
for cmd in curl jq op; do
  command -v "$cmd" >/dev/null || { echo "missing: $cmd" >&2; exit 1; }
done

OUT=${OUT:-"$HOME/phoenix-unifi-export/$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$OUT"
JAR=$(mktemp)
trap 'rm -f "$JAR"' EXIT

CURL=(curl --silent --show-error --max-time 20 --cookie "$JAR" --cookie-jar "$JAR")
[[ $INSECURE == yes ]] && CURL+=(--insecure)
BASE="https://${HOST}"

# --- Login (credentials never on a command line: jq reads them from its environment, which only
# this user can see, and curl from stdin) ----------------------------------------------------
user=$(op read "${OP_ITEM}/username")
pass=$(op read "${OP_ITEM}/password")
status=$(UNIFI_USER=$user UNIFI_PASS=$pass jq -n '{username: env.UNIFI_USER, password: env.UNIFI_PASS, rememberMe: false}' |
  "${CURL[@]}" -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    --data-binary @- "${BASE}/api/auth/login") || status="curl-failed"
unset user pass
if [[ $status != 200 ]]; then
  echo "login failed (HTTP ${status}). Check the account, its 'View Only' role, and --insecure if the certificate is self-signed." >&2
  exit 1
fi
logout() { "${CURL[@]}" -o /dev/null -X POST "${BASE}/api/auth/logout" || true; rm -f "$JAR"; }
trap logout EXIT

# --- Read-only exports -----------------------------------------------------------
# strip_secrets: delete every "x_*" key at any depth (UniFi's secret fields)
strip_secrets() { jq 'walk(if type == "object" then with_entries(select(.key | startswith("x_") | not)) else . end)'; }

declare -a SUMMARY=()
fetch() {  # fetch <name> <path> [jq filter]
  local name=$1 path=$2 filter=${3:-.} code tmp
  tmp=$(mktemp)
  code=$("${CURL[@]}" -o "$tmp" -w '%{http_code}' "${BASE}/proxy/network${path}") || code="curl-failed"
  if [[ $code == 200 ]] && jq -e . "$tmp" >/dev/null 2>&1; then
    strip_secrets <"$tmp" | jq "$filter" >"${OUT}/${name}.json"
    SUMMARY+=("ok    ${name}")
  else
    SUMMARY+=("skip  ${name} (HTTP ${code}: not on this UniFi version, or not allowed)")
  fi
  rm -f "$tmp"
}

fetch sysinfo            "/api/s/${SITE}/stat/sysinfo"
fetch networks           "/api/s/${SITE}/rest/networkconf"
fetch firewall-zones     "/v2/api/site/${SITE}/firewall/zone"
fetch firewall-policies  "/v2/api/site/${SITE}/firewall-policies"
fetch firewall-groups    "/api/s/${SITE}/rest/firewallgroup"
fetch firewall-rules-legacy "/api/s/${SITE}/rest/firewallrule"
fetch traffic-rules      "/v2/api/site/${SITE}/trafficrules"
fetch port-forwards      "/api/s/${SITE}/rest/portforward"
fetch port-profiles      "/api/s/${SITE}/rest/portconf"
# Local DNS records and DNS policies. UniFi 11 keeps a "Forward Domain" policy here as an NS
# record (key = the domain, value = the server), e.g. int.phoenixstack.net → dns01, dns02
# (checked on 11.0.104, 2026-11-26; there is no separate dns-policies endpoint).
fetch local-dns          "/v2/api/site/${SITE}/static-dns"
# Remote-access VPNs (Teleport, WireGuard/OpenVPN servers): only the site settings whose key
# names a VPN, so unrelated settings never leave the UDM. x_* secrets are stripped as everywhere.
fetch vpn-settings       "/api/s/${SITE}/rest/setting" \
  '{data: [.data[] | select(.key | test("teleport|vpn|wireguard|openvpn"; "i"))]}'
fetch vpn-servers        "/v2/api/site/${SITE}/vpn/servers"
# Devices: only what's needed to check switch ports (name, model, ports and their profiles)
fetch devices            "/api/s/${SITE}/stat/device" \
  '{data: [.data[] | {name, model, type, ip, mac, version,
     port_table: [(.port_table // [])[] | {port_idx, name, portconf_id, native_networkconf_id, tagged_vlan_mgmt, excluded_networkconf_ids, up, speed}]}]}'
# Clients: who holds which address (to find leftover 10.101.1.x leases)
fetch clients            "/api/s/${SITE}/stat/sta" \
  '{data: [.data[] | {name: (.name // .hostname), hostname, ip, mac, network, vlan, is_wired, fixed_ip, use_fixedip}]}'

printf '%s\n' "${SUMMARY[@]}"
echo "Saved to ${OUT}"
