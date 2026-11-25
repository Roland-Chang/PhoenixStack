#!/usr/bin/env bash
# =============================================================================
# prepare-iso.sh — build an unattended Proxmox VE 9 installer ISO for a node.
#
# Run as root on a Proxmox VE 9 / Debian 13 machine. Running it on the CURRENT
# pve01 is best: it can then prove the boot-disk and NIC filters match the real
# hardware before you wipe anything.
#
# Usage:
#   ./prepare-iso.sh --config ../config/pve01.conf \
#                    --iso /mnt/nas/nas-iso/template/iso/proxmox-ve_9.x-y.iso \
#                    --out /root/pve01-auto.iso
#   Options:  --skip-device-check   (when not running on the target hardware)
#
# The root password is prompted (never stored); only its SHA-512 crypt hash is
# embedded in the ISO. Delete the output ISO once the install is done.
# =============================================================================
set -Eeuo pipefail
umask 077

CONFIG="" ISO="" OUT="" DEVICE_CHECK="yes"
die() { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
trap 'die "failed (line $LINENO): $BASH_COMMAND"' ERR

while [[ $# -gt 0 ]]; do
  case $1 in
    --config) CONFIG=${2:?}; shift 2 ;;
    --iso)    ISO=${2:?}; shift 2 ;;
    --out)    OUT=${2:?}; shift 2 ;;
    --skip-device-check) DEVICE_CHECK="no"; shift ;;
    -h|--help) sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ $EUID -eq 0 ]] || die "run as root"
[[ -r $CONFIG ]] || die "--config <file> required"
[[ -r $ISO ]]    || die "--iso <proxmox-ve_9.x.iso> required"
[[ -n $OUT ]]    || die "--out <output.iso> required"
if grep -v '^[[:space:]]*#' "$CONFIG" | grep -q REPLACE_ME; then die "config still has REPLACE_ME placeholders"; fi
# shellcheck source=/dev/null
source "$CONFIG"

FQDN="${NODE_NAME}.${NODE_DOMAIN}"
# shellcheck disable=SC2153  # UPLINK_MACS comes from the sourced config
UPLINK_MAC=${UPLINK_MACS%% *}
MAC_FILTER="*$(tr -d ':' <<<"${UPLINK_MAC,,}")"
DNS1=${DNS_SERVERS%% *}

if ! command -v proxmox-auto-install-assistant >/dev/null; then
  echo "Installing proxmox-auto-install-assistant + xorriso..."
  apt-get update -q && apt-get install -y -q proxmox-auto-install-assistant xorriso
fi

# --- Prove the filters select the right hardware --------------------------------
if [[ $DEVICE_CHECK == yes ]]; then
  echo; echo "== Boot disks matched by ${INSTALL_DISK_FILTER} =="
  proxmox-auto-install-assistant device-match disk "$INSTALL_DISK_FILTER"
  echo; echo "== NIC matched by ID_NET_NAME_MAC=${MAC_FILTER} =="
  proxmox-auto-install-assistant device-match network "ID_NET_NAME_MAC=${MAC_FILTER}"
  echo
  read -r -p "Exactly the 2 Intel boot SSDs and the 1 uplink NIC above? Type 'yes': " a
  [[ $a == yes ]] || die "filters not confirmed — fix the config"
fi

# --- Root password -> hash ---------------------------------------------------------
read -r -s -p "New root password for ${FQDN} (store it in 1Password): " p1; echo
read -r -s -p "Again: " p2; echo
[[ $p1 == "$p2" ]] || die "passwords do not match"
((${#p1} >= 16)) || die "use at least 16 characters"
HASH=$(openssl passwd -6 -stdin <<<"$p1")
unset p1 p2

# --- Render answer.toml ------------------------------------------------------------
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
ANSWER="${WORK}/answer.toml"
{
  cat <<EOF
# PhoenixStack unattended install — ${FQDN} — generated $(date -Iseconds)
[global]
keyboard = "${INSTALL_KEYBOARD}"
country = "${INSTALL_COUNTRY}"
fqdn = "${FQDN}"
mailto = "${ROOT_EMAIL}"
timezone = "${TIMEZONE}"
root-password-hashed = "${HASH}"
reboot-on-error = false
root-ssh-keys = [
EOF
  for k in "${ROOT_SSH_KEYS[@]}"; do printf '  "%s",\n' "${k//\"/}"; done
  cat <<EOF
]

[network]
source = "from-answer"
cidr = "${MGMT_CIDR}"
gateway = "${MGMT_GATEWAY}"
dns = "${DNS1}"
filter.ID_NET_NAME_MAC = "${MAC_FILTER}"

[network.interface-name-pinning]
enabled = true

[disk-setup]
filesystem = "zfs"
zfs.raid = "${INSTALL_ZFS_RAID}"
zfs.ashift = 12
zfs.compress = "lz4"
zfs.arc-max = $((ZFS_ARC_MAX_GIB * 1024))
filter.${INSTALL_DISK_FILTER%%=*} = "${INSTALL_DISK_FILTER#*=}"
EOF
} >"$ANSWER"

echo; echo "== answer.toml (password hash redacted) =="
sed 's/^root-password-hashed = .*/root-password-hashed = "<redacted>"/' "$ANSWER"
echo
proxmox-auto-install-assistant validate-answer "$ANSWER"

# --- Build ISO -----------------------------------------------------------------------
proxmox-auto-install-assistant prepare-iso "$ISO" --fetch-from iso --answer-file "$ANSWER" --output "$OUT"
chmod 600 "$OUT" 2>/dev/null || true
echo
echo "Built: ${OUT}"
sha256sum "$OUT"
cat <<EOF

Next:
  * Mount ${OUT##*/} via iDRAC Virtual Media and boot it (UEFI). It picks
    "Automated Installation" on its own after a short countdown.
  * The ISO contains the root password hash — delete it after the install.
EOF
