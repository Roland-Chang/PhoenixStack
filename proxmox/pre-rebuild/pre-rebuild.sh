#!/usr/bin/env bash
# =============================================================================
# pre-rebuild.sh — run on the CURRENT pve01 before reinstalling it.
#
#   --capture         Save a read-only snapshot of the host's config/inventory to
#                     the NAS (no secrets: /etc/pve/priv, *.key, SSH host keys and
#                     SMB credential files are excluded).
#   --backup-guests   vzdump every guest to NAS storage and verify each archive.
#                     Default mode 'snapshot' (guests keep running).
#   --final           With --backup-guests: cleanly shut down ALL guests first and
#                     leave them off — use this for the cutover backup.
#   --storage <id>    vzdump storage (default: nas-dump)
#
# Typical flow:
#   ./pre-rebuild.sh --capture                     # any time, harmless
#   ./pre-rebuild.sh --backup-guests               # rehearsal, no downtime
#   ./pre-rebuild.sh --backup-guests --final       # cutover: downtime starts here
# =============================================================================
set -Eeuo pipefail
umask 027

CAPTURE="no" BACKUP="no" FINAL="no" STORAGE="nas-dump"
RUN_ID=$(date +%Y%m%d-%H%M%S)
die() { printf '\e[31mERROR:\e[0m %s\n' "$*" >&2; exit 1; }
trap 'die "failed (line $LINENO): $BASH_COMMAND"' ERR

while [[ $# -gt 0 ]]; do
  case $1 in
    --capture)       CAPTURE="yes"; shift ;;
    --backup-guests) BACKUP="yes"; shift ;;
    --final)         FINAL="yes"; shift ;;
    --storage)       STORAGE=${2:?}; shift 2 ;;
    -h|--help)       sed -n '2,/^# =====/p' "$0" | sed 's/^# \{0,1\}//; /^=====/d'; exit 0 ;;
    *)               die "unknown argument: $1" ;;
  esac
done
[[ $EUID -eq 0 ]] || die "run as root"
[[ $CAPTURE == yes || $BACKUP == yes ]] || die "nothing to do — use --capture and/or --backup-guests"
[[ $FINAL == no || $BACKUP == yes ]] || die "--final only applies with --backup-guests"

STORE_PATH=$(pvesh get "/storage/${STORAGE}" --output-format json | perl -MJSON::PP -0777 -ne 'print decode_json($_)->{path} // ""')
[[ -n $STORE_PATH && -d $STORE_PATH ]] || die "storage ${STORAGE} has no reachable path"

# ----------------------------------------------------------------------------
capture() {
  local dest="${STORE_PATH}/rebuild-${RUN_ID}"
  mkdir -p "$dest"
  echo "== Capturing host state to ${dest}"
  {
    echo "### pveversion -v";            pveversion -v
    echo; echo "### NIC MACs (fill UPLINK_MACS)"
    for n in /sys/class/net/*; do [[ -e $n/device ]] && printf '%-8s %s  speed=%s carrier=%s\n' \
      "$(basename "$n")" "$(cat "$n/address")" "$(cat "$n/speed" 2>/dev/null || echo ?)" "$(cat "$n/carrier" 2>/dev/null || echo ?)"; done
    echo; echo "### ip -br addr";        ip -br addr
    echo; echo "### disks";              lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,WWN,TRAN,FSTYPE,MOUNTPOINTS
    echo; echo "### /dev/disk/by-id";    ls -l /dev/disk/by-id/ | grep -v -- '-part[0-9]'
    echo; echo "### zpool status";       zpool status
    echo; echo "### zfs list";           zfs list -o name,used,avail,refer,mountpoint
    echo; echo "### /var/lib/vz usage";  du -xh --max-depth=2 /var/lib/vz 2>/dev/null | sort -h | tail -25
    echo; echo "### pvesm status";       pvesm status
    echo; echo "### guests";             qm list; pct list
    echo; echo "### PCI";                lspci -nnk
    echo; echo "### root authorized_keys (public keys)"; cat /root/.ssh/authorized_keys 2>/dev/null || true
    echo; echo "### manually installed packages"; apt-mark showmanual | sort
    echo; echo "### NVIDIA/CUDA packages"; dpkg -l | awk '/nvidia|cuda/ {print $2, $3}'
    echo; echo "### enabled services";  systemctl list-unit-files --state=enabled --type=service --no-legend
    echo; echo "### root crontab";       crontab -l 2>/dev/null || echo "(none)"
  } >"${dest}/host-inventory.txt" 2>&1

  tar -czf "${dest}/etc-snapshot.tgz" \
    --exclude='/etc/pve/priv' --exclude='*.key' --exclude='/etc/ssh/ssh_host_*' \
    --exclude='*credentials*' --exclude='*.cred' --exclude='*.pw' \
    /etc/pve /etc/network /etc/hosts /etc/modprobe.d /etc/modules* /etc/kernel \
    /etc/default/grub /etc/apt /etc/cron* /etc/sysctl.d /etc/vzdump.conf 2>/dev/null || true
  # fstab may embed CIFS passwords inline — keep only a redacted copy
  sed -E 's/(pass(word)?=)[^,[:space:]]+/\1***REDACTED***/g' /etc/fstab >"${dest}/fstab.redacted"
  if grep -qE 'pass(word)?=' /etc/fstab; then
    echo "  ! /etc/fstab has inline SMB passwords — rotate that SMB account after the rebuild"
  fi
  echo "  wrote: host-inventory.txt, etc-snapshot.tgz, fstab.redacted"
  echo
  echo "  Uplink MACs (for UPLINK_MACS in pve01.conf):"
  grep -E '^nic[0-9]|^en' "${dest}/host-inventory.txt" | sed 's/^/    /' || true
  echo "  /var/lib/vz (wiped by the reinstall — copy anything you want to keep):"
  du -xh --max-depth=1 /var/lib/vz 2>/dev/null | sort -h | sed 's/^/    /'
}

# ----------------------------------------------------------------------------
backup_guests() {
  local -a ids running
  mapfile -t ids < <( { qm list | awk 'NR>1{print $1}'; pct list | awk 'NR>1{print $1}'; } | sort -n)
  ((${#ids[@]})) || die "no guests found"
  mapfile -t running < <( { qm list | awk 'NR>1 && $3=="running"{print $1}'; pct list | awk 'NR>1 && $2=="running"{print $1}'; } | sort -n)

  echo "== Guests to back up to ${STORAGE} (${STORE_PATH}/dump)"
  qm list; pct list
  echo "  free on ${STORAGE}: $(df -h --output=avail "$STORE_PATH" | tail -1 | tr -d ' ')"

  if [[ $FINAL == yes ]]; then
    printf '\n\e[33mFINAL: all running guests (%s) will be shut down and LEFT OFF.\e[0m\n' "${running[*]:-none}"
    read -r -p "Type 'shutdown' to continue: " a; [[ $a == shutdown ]] || die "aborted"
    local id
    for id in "${running[@]}"; do
      echo "  shutting down ${id}..."
      if qm status "$id" >/dev/null 2>&1; then qm shutdown "$id" --timeout 300 || qm stop "$id"
      else pct shutdown "$id" --timeout 300 || pct stop "$id"; fi
    done
  fi

  local mode="snapshot"; [[ $FINAL == yes ]] && mode="stop"
  echo "== vzdump (mode=${mode})"
  vzdump "${ids[@]}" --storage "$STORAGE" --mode "$mode" --compress zstd --zstd 0 \
    --prune-backups keep-all=1 --notes-template "{{guestname}} pre-rebuild ${RUN_ID}"

  echo "== Verifying archives"
  local f fail=0
  for id in "${ids[@]}"; do
    f=$(ls -1t "${STORE_PATH}"/dump/vzdump-*-"${id}"-*.zst 2>/dev/null | head -1 || true)
    if [[ -z $f ]]; then echo "  ✗ ${id}: no archive found"; fail=1; continue; fi
    if zstd -tq "$f"; then echo "  ✓ ${id}: $(du -h "$f" | cut -f1)  ${f##*/}"
    else echo "  ✗ ${id}: CORRUPT ${f##*/}"; fail=1; fi
  done
  ((fail == 0)) || die "one or more backups failed verification — do NOT proceed with the rebuild"
  echo
  echo "All ${#ids[@]} guest backups verified. Note: LXC bind mounts (mpX to host paths) are"
  echo "never included in vzdump — that data lives on the NAS already."
  if [[ $FINAL == yes ]]; then echo "Guests are OFF. Safe to proceed with the reinstall."; fi
}

[[ $CAPTURE == yes ]] && capture
[[ $BACKUP == yes ]] && backup_guests
exit 0
